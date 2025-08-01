defmodule Orchard.SimulatorSupervisor do
  @moduledoc """
  Supervisor for managing SimulatorServer processes.
  
  This supervisor uses a dynamic supervisor pattern to start and stop
  SimulatorServer processes on demand.
  """
  
  use DynamicSupervisor
  
  alias Orchard.SimulatorServer
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  @doc """
  Starts a new SimulatorServer for the given simulator.
  """
  def start_simulator(simulator_info) do
    spec = {SimulatorServer, simulator_info}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
  
  @doc """
  Stops the SimulatorServer for the given UDID.
  """
  def stop_simulator(udid) do
    case Registry.lookup(Orchard.SimulatorRegistry, udid) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] ->
        {:error, :not_found}
    end
  end
  
  @doc """
  Lists all active simulator servers.
  """
  def list_active_simulators do
    children = DynamicSupervisor.which_children(__MODULE__)
    
    Enum.map(children, fn {_, pid, _, _} ->
      case GenServer.call(pid, :get_state) do
        {:ok, state} -> state
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
  
  @doc """
  Finds a simulator server by UDID.
  """
  def find_simulator(udid) do
    case Registry.lookup(Orchard.SimulatorRegistry, udid) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end