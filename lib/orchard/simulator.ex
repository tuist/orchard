defmodule Orchard.Simulator do
  @moduledoc """
  Module for managing iOS simulators using AXe CLI.

  This module provides functions to list, boot, and manage simulators.
  When a simulator is booted, a SimulatorServer GenServer is started
  to manage its lifecycle.
  """

  alias Orchard.{Config, CpuInfo, Downloader, SimulatorServer, SimulatorSupervisor}

  defstruct [:name, :udid, :state, :device_type, :runtime]

  @type t :: %__MODULE__{
          name: String.t(),
          udid: String.t(),
          state: String.t(),
          device_type: String.t(),
          runtime: String.t()
        }

  @doc """
  Lists all available simulators.

  Returns a list of simulator structs.
  """
  @spec list() :: {:ok, [t()]} | {:error, String.t()}
  def list do
    if CpuInfo.supported_platform?() do
      with :ok <- Downloader.ensure_available() do
        case MuonTrap.cmd(Config.axe_cmd(), ["list-simulators"]) do
          {output, 0} ->
            simulators = parse_simulators(output)
            {:ok, simulators}

          {error, _} ->
            {:error, "Failed to list simulators: #{error}"}
        end
      end
    else
      {:error, CpuInfo.unsupported_platform_error()}
    end
  rescue
    _ -> {:error, "Failed to execute AXe command"}
  end

  @doc """
  Lists only booted simulators.
  """
  @spec list_booted() :: {:ok, [t()]} | {:error, String.t()}
  def list_booted do
    case list() do
      {:ok, simulators} ->
        booted = Enum.filter(simulators, fn sim -> sim.state == "Booted" end)
        {:ok, booted}

      error ->
        error
    end
  end

  @doc """
  Finds a simulator by its name or UDID.
  """
  @spec find(String.t()) :: {:ok, t()} | {:error, String.t()}
  def find(identifier) do
    case list() do
      {:ok, simulators} ->
        simulator =
          Enum.find(simulators, fn sim ->
            sim.name == identifier || sim.udid == identifier
          end)

        if simulator do
          {:ok, simulator}
        else
          {:error, "Simulator not found: #{identifier}"}
        end

      error ->
        error
    end
  end

  @doc """
  Boots a simulator.
  """
  @spec boot(String.t() | t()) :: {:ok, t()} | {:error, String.t()}
  def boot(%__MODULE__{} = simulator) do
    # Start a SimulatorServer for this simulator if not already running
    case SimulatorSupervisor.find_simulator(simulator.udid) do
      {:ok, _pid} ->
        # Server already running, just boot it
        SimulatorServer.boot(simulator.udid)

      {:error, :not_found} ->
        # Start the server first
        case SimulatorSupervisor.start_simulator(simulator) do
          {:ok, _pid} ->
            SimulatorServer.boot(simulator.udid)

          {:error, reason} ->
            {:error, "Failed to start simulator server: #{inspect(reason)}"}
        end
    end
  end

  def boot(identifier) when is_binary(identifier) do
    case find(identifier) do
      {:ok, simulator} -> boot(simulator)
      error -> error
    end
  end

  @doc """
  Shuts down a simulator.
  """
  @spec shutdown(String.t() | t()) :: :ok | {:error, String.t()}
  def shutdown(%__MODULE__{udid: udid}) do
    case SimulatorSupervisor.find_simulator(udid) do
      {:ok, _pid} ->
        SimulatorServer.shutdown(udid)

      {:error, :not_found} ->
        {:error, "Simulator server not running"}
    end
  end

  def shutdown(identifier) when is_binary(identifier) do
    case find(identifier) do
      {:ok, simulator} -> shutdown(simulator)
      error -> error
    end
  end

  @doc """
  Erases a simulator's contents and settings.
  """
  @spec erase(String.t() | t()) :: :ok | {:error, String.t()}
  def erase(%__MODULE__{udid: udid}) do
    # Stop the server if running
    SimulatorSupervisor.stop_simulator(udid)

    with :ok <- Downloader.ensure_available() do
      case MuonTrap.cmd("xcrun", ["simctl", "erase", udid]) do
        {_, 0} ->
          :ok

        {error, _} ->
          {:error, "Failed to erase simulator: #{error}"}
      end
    end
  end

  def erase(identifier) when is_binary(identifier) do
    case find(identifier) do
      {:ok, simulator} -> erase(simulator)
      error -> error
    end
  end

  @doc """
  Installs an app on the simulator.
  """
  @spec install_app(t(), String.t()) :: :ok | {:error, String.t()}
  def install_app(%__MODULE__{udid: udid}, app_path) do
    case SimulatorSupervisor.find_simulator(udid) do
      {:ok, _pid} ->
        SimulatorServer.install_app(udid, app_path)

      {:error, :not_found} ->
        {:error, "Simulator server not running"}
    end
  end

  @doc """
  Uninstalls an app from the simulator.
  """
  @spec uninstall_app(t(), String.t()) :: :ok | {:error, String.t()}
  def uninstall_app(%__MODULE__{udid: udid}, bundle_id) do
    with :ok <- Downloader.ensure_available() do
      case MuonTrap.cmd("xcrun", ["simctl", "uninstall", udid, bundle_id]) do
        {_, 0} ->
          :ok

        {error, _} ->
          {:error, "Failed to uninstall app: #{error}"}
      end
    end
  end

  @doc """
  Launches an app on the simulator.
  """
  @spec launch_app(t(), String.t(), [String.t()]) :: :ok | {:error, String.t()}
  def launch_app(%__MODULE__{udid: udid}, bundle_id, args \\ []) do
    case SimulatorSupervisor.find_simulator(udid) do
      {:ok, _pid} ->
        SimulatorServer.launch_app(udid, bundle_id, args)

      {:error, :not_found} ->
        {:error, "Simulator server not running"}
    end
  end

  @doc """
  Takes a screenshot of the simulator.
  """
  @spec screenshot(t(), String.t()) :: :ok | {:error, String.t()}
  def screenshot(%__MODULE__{udid: udid}, output_path) do
    case SimulatorSupervisor.find_simulator(udid) do
      {:ok, _pid} ->
        SimulatorServer.screenshot(udid, output_path)

      {:error, :not_found} ->
        {:error, "Simulator server not running"}
    end
  end

  @doc """
  Records video from the simulator.
  Returns the PID of the recording process.
  """
  @spec start_recording(t(), String.t()) :: {:ok, pid()} | {:error, String.t()}
  def start_recording(%__MODULE__{udid: udid}, output_path) do
    with :ok <- Downloader.ensure_available() do
      {:ok, _pid} =
        MuonTrap.Daemon.start_link("xcrun", ["simctl", "io", udid, "recordVideo", output_path])
    end
  rescue
    e -> {:error, "Failed to start recording: #{inspect(e)}"}
  end

  @doc """
  Stops video recording.
  """
  @spec stop_recording(pid()) :: :ok
  def stop_recording(pid) when is_pid(pid) do
    GenServer.stop(pid)
    :ok
  end

  defp parse_simulators(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_simulator_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_simulator_line(line) do
    # AXe output format: UDID | Name | State | Device Type | Runtime
    case String.split(line, " | ") do
      [udid, name, state, device_type, runtime] ->
        %__MODULE__{
          udid: String.trim(udid),
          name: String.trim(name),
          state: String.trim(state),
          device_type: String.trim(device_type),
          runtime: String.trim(runtime)
        }

      _ ->
        nil
    end
  end

  @doc """
  UI automation functions using AXe
  """
  def tap(%__MODULE__{udid: udid}, x, y) do
    case SimulatorSupervisor.find_simulator(udid) do
      {:ok, _pid} ->
        SimulatorServer.tap(udid, x, y)

      {:error, :not_found} ->
        {:error, "Simulator server not running"}
    end
  end

  def type_text(%__MODULE__{udid: udid}, text) do
    case SimulatorSupervisor.find_simulator(udid) do
      {:ok, _pid} ->
        SimulatorServer.type_text(udid, text)

      {:error, :not_found} ->
        {:error, "Simulator server not running"}
    end
  end

  @doc """
  Gets UI hierarchy description from AXe
  """
  def describe_ui(%__MODULE__{udid: udid}) do
    with :ok <- Downloader.ensure_available() do
      case MuonTrap.cmd(Config.axe_cmd(), ["describe-ui", "--udid", udid]) do
        {output, 0} ->
          {:ok, output}

        {error, _} ->
          {:error, "Failed to describe UI: #{error}"}
      end
    end
  end
end
