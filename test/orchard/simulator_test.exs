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

  # Integration tests that run on CI with real simulators
  describe "integration tests" do
    @describetag :integration

    setup do
      # Start a fresh application instance for each test
      Application.stop(:orchard)
      {:ok, _} = Application.ensure_all_started(:orchard)
      
      # Create a test simulator
      test_sim_udid = create_test_simulator()
      
      on_exit(fn ->
        # Clean up the test simulator
        if test_sim_udid do
          delete_test_simulator(test_sim_udid)
        end
        
        # Stop the application
        Application.stop(:orchard)
      end)
      
      {:ok, test_sim_udid: test_sim_udid}
    end

    test "lists available simulators including test simulator", %{test_sim_udid: test_sim_udid} do
      case Simulator.list() do
        {:ok, simulators} ->
          assert is_list(simulators)
          
          if test_sim_udid do
            # Should find our test simulator
            test_sim = Enum.find(simulators, fn s -> s.udid == test_sim_udid end)
            assert test_sim != nil
            assert test_sim.name =~ "OrchardTest"
          end

        {:error, reason} ->
          # On non-macOS systems, this should fail gracefully
          assert reason =~ "only supported on macOS" or reason =~ "Failed to execute AXe"
      end
    end

    test "simulator lifecycle management with test simulator", %{test_sim_udid: test_sim_udid} do
      # Skip if no test simulator was created (non-macOS)
      if test_sim_udid == nil do
        :ok
      else
        # Get the test simulator
        {:ok, simulators} = Simulator.list()
        test_sim = Enum.find(simulators, fn s -> s.udid == test_sim_udid end)
        assert test_sim != nil
        assert test_sim.state == "Shutdown"
        
        # Boot the simulator
        assert {:ok, booted_sim} = Simulator.boot(test_sim)
        
        # Give it time to boot
        Process.sleep(3000)
        
        # Verify it's actually booted
        {:ok, current_sims} = Simulator.list()
        current_sim = Enum.find(current_sims, fn s -> s.udid == test_sim_udid end)
        assert current_sim.state == "Booted"

        # Verify a GenServer was started for this simulator
        assert {:ok, pid} = Simulator.get_server(test_sim_udid)
        assert Process.alive?(pid)

        # Shutdown the simulator
        assert :ok = Simulator.shutdown(booted_sim)

        # Wait for shutdown
        Process.sleep(3000)

        # Verify the GenServer stopped
        assert {:error, :not_found} = Simulator.get_server(test_sim_udid)
        
        # Verify simulator is actually shutdown
        {:ok, final_sims} = Simulator.list()
        final_sim = Enum.find(final_sims, fn s -> s.udid == test_sim_udid end)
        assert final_sim.state == "Shutdown"
      end
    end

    test "booted simulators list", %{test_sim_udid: test_sim_udid} do
      if test_sim_udid do
        # Boot our test simulator
        {:ok, simulators} = Simulator.list()
        test_sim = Enum.find(simulators, fn s -> s.udid == test_sim_udid end)
        
        if test_sim do
          {:ok, _} = Simulator.boot(test_sim)
          Process.sleep(3000)
          
          # Now check booted list
          case Simulator.list_booted() do
            {:ok, booted} ->
              assert is_list(booted)
              # All returned simulators should be booted
              Enum.each(booted, fn sim ->
                assert sim.state == "Booted"
              end)
              
              # Our test simulator should be in the list
              assert Enum.any?(booted, fn s -> s.udid == test_sim_udid end)
              
              # Clean up
              Simulator.shutdown(test_sim)
              
            {:error, _reason} ->
              # Might fail if AXe has issues
              :ok
          end
        end
      else
        # No test simulator on non-macOS
        case Simulator.list_booted() do
          {:ok, booted} ->
            assert is_list(booted)
            Enum.each(booted, fn sim ->
              assert sim.state == "Booted"
            end)

          {:error, reason} ->
            assert reason =~ "only supported on macOS" or reason =~ "Failed to execute AXe"
        end
      end
    end

    test "simulator server monitoring with test simulator", %{test_sim_udid: test_sim_udid} do
      if test_sim_udid do
        # Get the test simulator
        {:ok, simulators} = Simulator.list()
        test_sim = Enum.find(simulators, fn s -> s.udid == test_sim_udid end)
        
        if test_sim do
          # Ensure no server is running
          assert {:error, :not_found} = Simulator.get_server(test_sim_udid)
          
          # Start monitoring the simulator
          {:ok, _} = Orchard.SimulatorSupervisor.start_simulator(test_sim)

          # Verify the server is running
          assert {:ok, pid} = Simulator.get_server(test_sim_udid)
          assert Process.alive?(pid)

          # Stop the server
          :ok = Orchard.SimulatorSupervisor.stop_simulator(test_sim_udid)

          # Verify it's stopped
          Process.sleep(100)
          assert {:error, :not_found} = Simulator.get_server(test_sim_udid)
        end
      else
        # Skip on non-macOS
        :ok
      end
    end
  end

  # Helper functions for creating/deleting test simulators
  defp create_test_simulator do
    if :os.type() == {:unix, :darwin} do
      # Get available device types and runtimes
      {device_types_output, 0} = System.cmd("xcrun", ["simctl", "list", "devicetypes"])
      {runtimes_output, 0} = System.cmd("xcrun", ["simctl", "list", "runtimes"])
      
      # Find a suitable iPhone device type
      device_type = find_iphone_device_type(device_types_output)
      
      # Find a suitable iOS runtime
      runtime = find_ios_runtime(runtimes_output)
      
      if device_type && runtime do
        # Create a uniquely named simulator for testing
        timestamp = System.system_time(:second)
        sim_name = "OrchardTest-#{timestamp}"
        
        case System.cmd("xcrun", ["simctl", "create", sim_name, device_type, runtime]) do
          {udid, 0} ->
            String.trim(udid)
          _ ->
            nil
        end
      else
        nil
      end
    else
      nil
    end
  end

  defp delete_test_simulator(udid) do
    # First shutdown if it's running
    System.cmd("xcrun", ["simctl", "shutdown", udid])
    Process.sleep(1000)
    
    # Then delete it
    System.cmd("xcrun", ["simctl", "delete", udid])
  end

  defp find_iphone_device_type(output) do
    # Look for iPhone device types in the output
    # Example: iPhone 15 (com.apple.CoreSimulator.SimDeviceType.iPhone-15)
    case Regex.run(~r/iPhone[^\(]+\((com\.apple\.CoreSimulator\.SimDeviceType\.iPhone[^\)]+)\)/, output) do
      [_, device_type] -> device_type
      _ -> nil
    end
  end

  defp find_ios_runtime(output) do
    # Look for iOS runtimes in the output
    # Example: iOS 17.5 (17.5 - 21F79) - com.apple.CoreSimulator.SimRuntime.iOS-17-5
    case Regex.run(~r/iOS[^\(]+\([^\)]+\)[^c]+(com\.apple\.CoreSimulator\.SimRuntime\.iOS[^\s]+)/, output) do
      [_, runtime] -> runtime
      _ -> nil
    end
  end
end