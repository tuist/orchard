defmodule Orchard.SimulatorTest do
  use ExUnit.Case
  alias Orchard.Simulator

  describe "Simulator struct" do
    test "creates a simulator struct with all fields" do
      simulator = %Simulator{
        name: "iPhone 15",
        udid: "87654321-4321-4321-4321-210987654321",
        state: "Shutdown",
        device_type: "com.apple.CoreSimulator.SimDeviceType.iPhone-15",
        runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-0"
      }

      assert simulator.name == "iPhone 15"
      assert simulator.udid == "87654321-4321-4321-4321-210987654321"
      assert simulator.state == "Shutdown"
      assert simulator.device_type == "com.apple.CoreSimulator.SimDeviceType.iPhone-15"
      assert simulator.runtime == "com.apple.CoreSimulator.SimRuntime.iOS-17-0"
    end
  end
end
