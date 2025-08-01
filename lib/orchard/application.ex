defmodule Orchard.Application do
  @moduledoc """
  The main Orchard application.

  This application starts the supervision tree for managing
  simulators and devices.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for simulator servers
      {Registry, keys: :unique, name: Orchard.SimulatorRegistry},

      # Registry for device servers (if we support devices)
      {Registry, keys: :unique, name: Orchard.DeviceRegistry},

      # Dynamic supervisor for simulators
      Orchard.SimulatorSupervisor

      # Note: DeviceSupervisor will be added when device support is implemented
    ]

    opts = [strategy: :one_for_one, name: Orchard.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
