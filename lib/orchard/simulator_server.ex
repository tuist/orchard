defmodule Orchard.SimulatorServer do
  @moduledoc """
  GenServer that manages the lifecycle of a single simulator.

  This server:
  - Launches and manages a simulator process
  - Monitors the simulator's state
  - Automatically terminates if the simulator shuts down
  - Provides an interface for simulator operations
  """

  use GenServer
  require Logger

  alias Orchard.{Config, Downloader}

  # Check simulator state every second
  @check_interval 1_000

  defstruct [:udid, :name, :device_type, :runtime, :state, :monitor_ref]

  @type t :: %__MODULE__{
          udid: String.t(),
          name: String.t(),
          device_type: String.t(),
          runtime: String.t(),
          state: String.t(),
          monitor_ref: reference() | nil
        }

  # Client API

  @doc """
  Starts a SimulatorServer for the given simulator.
  """
  def start_link(simulator_info) do
    GenServer.start_link(__MODULE__, simulator_info, name: via_tuple(simulator_info.udid))
  end

  @doc """
  Boots the simulator if it's not already booted.
  """
  def boot(udid) do
    GenServer.call(via_tuple(udid), :boot, 30_000)
  end

  @doc """
  Shuts down the simulator.
  """
  def shutdown(udid) do
    GenServer.call(via_tuple(udid), :shutdown)
  end

  @doc """
  Installs an app on the simulator.
  """
  def install_app(udid, app_path) do
    GenServer.call(via_tuple(udid), {:install_app, app_path})
  end

  @doc """
  Launches an app on the simulator.
  """
  def launch_app(udid, bundle_id, args \\ []) do
    GenServer.call(via_tuple(udid), {:launch_app, bundle_id, args})
  end

  @doc """
  Gets the current state of the simulator.
  """
  def get_state(udid) do
    GenServer.call(via_tuple(udid), :get_state)
  end

  @doc """
  Takes a screenshot of the simulator.
  """
  def screenshot(udid, output_path) do
    GenServer.call(via_tuple(udid), {:screenshot, output_path})
  end

  @doc """
  Performs a tap at the given coordinates.
  """
  def tap(udid, x, y) do
    GenServer.call(via_tuple(udid), {:tap, x, y})
  end

  @doc """
  Types text on the simulator.
  """
  def type_text(udid, text) do
    GenServer.call(via_tuple(udid), {:type_text, text})
  end

  # Server Callbacks

  @impl true
  def init(simulator_info) do
    # Ensure AXe is available
    case Downloader.ensure_available() do
      :ok ->
        state = %__MODULE__{
          udid: simulator_info.udid,
          name: simulator_info.name,
          device_type: simulator_info.device_type,
          runtime: simulator_info.runtime,
          state: simulator_info.state || "Shutdown"
        }

        # Schedule first state check
        Process.send_after(self(), :check_state, @check_interval)

        {:ok, state}

      {:error, reason} ->
        {:stop, {:error, reason}}
    end
  end

  @impl true
  def handle_call(:boot, _from, state) do
    if state.state == "Booted" do
      {:reply, {:ok, state}, state}
    else
      case boot_simulator(state.udid) do
        :ok ->
          new_state = %{state | state: "Booted"}
          {:reply, {:ok, new_state}, new_state}

        {:error, _reason} = error ->
          {:reply, error, state}
      end
    end
  end

  @impl true
  def handle_call(:shutdown, _from, state) do
    case shutdown_simulator(state.udid) do
      :ok ->
        # Stop the server after shutting down the simulator
        {:stop, :normal, :ok, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:install_app, app_path}, _from, state) do
    result = install_app_on_simulator(state.udid, app_path)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:launch_app, bundle_id, args}, _from, state) do
    result = launch_app_on_simulator(state.udid, bundle_id, args)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call({:screenshot, output_path}, _from, state) do
    result = take_screenshot(state.udid, output_path)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:tap, x, y}, _from, state) do
    result = perform_tap(state.udid, x, y)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:type_text, text}, _from, state) do
    result = type_text_on_simulator(state.udid, text)
    {:reply, result, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "SimulatorServer for #{state.name} (#{state.udid}) terminating: #{inspect(reason)}"
    )

    :ok
  end

  @impl true
  def handle_info(:check_state, state) do
    # Check if simulator is still in the system
    case get_simulator_state(state.udid) do
      {:ok, current_state} ->
        # Schedule next check
        Process.send_after(self(), :check_state, @check_interval)

        # Update state if changed
        if current_state != state.state do
          Logger.info(
            "Simulator #{state.name} (#{state.udid}) state changed: #{state.state} -> #{current_state}"
          )

          {:noreply, %{state | state: current_state}}
        else
          {:noreply, state}
        end

      {:error, :not_found} ->
        # Simulator no longer exists, terminate
        Logger.info(
          "Simulator #{state.name} (#{state.udid}) no longer exists, terminating server"
        )

        {:stop, :normal, state}

      {:error, reason} ->
        Logger.error("Failed to check simulator state: #{reason}")
        # Schedule next check anyway
        Process.send_after(self(), :check_state, @check_interval)
        {:noreply, state}
    end
  end

  # Private functions

  defp via_tuple(udid) do
    {:via, Registry, {Orchard.SimulatorRegistry, udid}}
  end

  defp boot_simulator(udid) do
    case MuonTrap.cmd("xcrun", ["simctl", "boot", udid]) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  defp shutdown_simulator(udid) do
    case MuonTrap.cmd("xcrun", ["simctl", "shutdown", udid]) do
      {_, 0} ->
        :ok

      {error, exit_code} ->
        # If the simulator is already shutdown, that's ok
        if String.contains?(error, "current state: Shutdown") do
          :ok
        else
          {:error, "Exit code #{exit_code}: #{error}"}
        end
    end
  end

  defp install_app_on_simulator(udid, app_path) do
    case MuonTrap.cmd("xcrun", ["simctl", "install", udid, app_path]) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  defp launch_app_on_simulator(udid, bundle_id, args) do
    cmd_args = ["simctl", "launch", udid, bundle_id] ++ args

    case MuonTrap.cmd("xcrun", cmd_args) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  defp take_screenshot(udid, output_path) do
    # Note: AXe doesn't have a screenshot command, we'll use simctl directly
    case MuonTrap.cmd("xcrun", ["simctl", "io", udid, "screenshot", output_path]) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  defp perform_tap(udid, x, y) do
    with :ok <- Downloader.ensure_available() do
      case MuonTrap.cmd(Config.axe_cmd(), [
             "tap",
             "--udid",
             udid,
             "--x",
             to_string(x),
             "--y",
             to_string(y)
           ]) do
        {_, 0} -> :ok
        {error, _} -> {:error, error}
      end
    end
  end

  defp type_text_on_simulator(udid, text) do
    with :ok <- Downloader.ensure_available() do
      case MuonTrap.cmd(Config.axe_cmd(), ["type", "--udid", udid, "--text", text]) do
        {_, 0} -> :ok
        {error, _} -> {:error, error}
      end
    end
  end

  defp get_simulator_state(udid) do
    with :ok <- Downloader.ensure_available() do
      case MuonTrap.cmd(Config.axe_cmd(), ["list-simulators"]) do
        {output, 0} ->
          # Parse the output to find our simulator
          lines = String.split(output, "\n", trim: true)

          simulator_line =
            Enum.find(lines, fn line ->
              String.starts_with?(line, udid)
            end)

          if simulator_line do
            # Parse the state from the line
            parts = String.split(simulator_line, " | ")
            state = Enum.at(parts, 2, "Unknown")
            {:ok, state}
          else
            {:error, :not_found}
          end

        {error, _} ->
          {:error, error}
      end
    end
  end
end
