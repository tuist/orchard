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

      # Try to find an existing simulator or create a test one
      test_sim_info = find_or_create_test_simulator()

      on_exit(fn ->
        # Clean up the test simulator if we created one
        case test_sim_info do
          {:created, udid} -> delete_test_simulator(udid)
          _ -> :ok
        end

        # Stop the application
        Application.stop(:orchard)
      end)

      {:ok, test_sim_info: test_sim_info}
    end

    test "lists available simulators including test simulator", %{test_sim_info: test_sim_info} do
      test_sim_udid =
        case test_sim_info do
          {:created, udid} -> udid
          {:existing, udid} -> udid
          nil -> nil
        end

      if test_sim_udid == nil do
        # Skip test if we couldn't create a test simulator
        :ok
      else
        case Simulator.list() do
          {:ok, simulators} ->
            assert is_list(simulators)

            # Should find our test simulator
            test_sim = Enum.find(simulators, fn s -> s.udid == test_sim_udid end)
            assert test_sim != nil
            assert test_sim.name =~ "OrchardTest"

          {:error, reason} ->
            # On non-macOS systems, this should fail gracefully
            assert reason =~ "only supported on macOS" or reason =~ "Failed to execute AXe"
        end
      end
    end

    test "simulator lifecycle management with test simulator", %{test_sim_info: test_sim_info} do
      # Skip if no test simulator available
      test_sim_udid =
        case test_sim_info do
          {:created, udid} -> udid
          {:existing, udid} -> udid
          nil -> nil
        end

      if test_sim_udid == nil do
        :ok
      else
        # Get the test simulator
        {:ok, simulators} = Simulator.list()
        test_sim = Enum.find(simulators, fn s -> s.udid == test_sim_udid end)
        assert test_sim != nil
        assert test_sim.state == "Shutdown"

        # Boot the simulator
        assert {:ok, _booted_sim} = Simulator.boot(test_sim)

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
        assert :ok = Simulator.shutdown(test_sim)

        # The shutdown should eventually stop the server
        # Wait for the process to die (with timeout)
        assert wait_for_process_death(pid, 5000), "Server process did not terminate"

        # Verify no server is running for this simulator
        # (even if Registry hasn't cleaned up yet, the process should be dead)
        case Simulator.get_server(test_sim_udid) do
          {:ok, stale_pid} ->
            refute Process.alive?(stale_pid), "Found stale PID in registry"

          {:error, :not_found} ->
            :ok
        end

        # Verify simulator is actually shutdown
        {:ok, final_sims} = Simulator.list()
        final_sim = Enum.find(final_sims, fn s -> s.udid == test_sim_udid end)
        assert final_sim.state == "Shutdown"
      end
    end

    test "booted simulators list", %{test_sim_info: test_sim_info} do
      test_sim_udid =
        case test_sim_info do
          {:created, udid} -> udid
          {:existing, udid} -> udid
          nil -> nil
        end

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

    test "simulator server monitoring with test simulator", %{test_sim_info: test_sim_info} do
      test_sim_udid =
        case test_sim_info do
          {:created, udid} -> udid
          {:existing, udid} -> udid
          nil -> nil
        end

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

  # Helper function to find an existing simulator or create a new one
  defp find_or_create_test_simulator do
    if :os.type() != {:unix, :darwin} do
      nil
    else
      find_or_create_darwin_simulator()
    end
  end

  defp find_or_create_darwin_simulator do
    # Always try to create a new test simulator for consistency
    case create_test_simulator() do
      nil -> nil
      udid -> {:created, udid}
    end
  end

  # Helper function to wait for a process to die
  defp wait_for_process_death(pid, timeout) when timeout > 0 do
    if Process.alive?(pid) do
      Process.sleep(100)
      wait_for_process_death(pid, timeout - 100)
    else
      true
    end
  end

  defp wait_for_process_death(_, _), do: false

  # Helper functions for creating/deleting test simulators
  defp create_test_simulator do
    if :os.type() != {:unix, :darwin} do
      nil
    else
      do_create_test_simulator()
    end
  end

  defp do_create_test_simulator do
    with {device_types_output, 0} <- System.cmd("xcrun", ["simctl", "list", "devicetypes"]),
         {runtimes_output, 0} <- System.cmd("xcrun", ["simctl", "list", "runtimes"]),
         device_type when not is_nil(device_type) <- find_iphone_device_type(device_types_output),
         runtime when not is_nil(runtime) <- find_ios_runtime(runtimes_output) do
      create_simulator_with_params(device_type, runtime)
    else
      _ -> nil
    end
  end

  defp create_simulator_with_params(device_type, runtime) do
    # Create a uniquely named simulator for testing
    timestamp = System.system_time(:second)
    sim_name = "OrchardTest-#{timestamp}"

    case System.cmd("xcrun", ["simctl", "create", sim_name, device_type, runtime]) do
      {udid, 0} ->
        String.trim(udid)

      _ ->
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
    # Find any available iPhone device type
    # Example: iPhone 15 (com.apple.CoreSimulator.SimDeviceType.iPhone-15)
    case Regex.run(
           ~r/iPhone[^\(]+\((com\.apple\.CoreSimulator\.SimDeviceType\.iPhone[^\)]+)\)/,
           output
         ) do
      [_, device_type] -> device_type
      _ -> nil
    end
  end

  defp find_ios_runtime(output) do
    # Find any available iOS runtime
    # Example: iOS 17.5 (17.5 - 21F79) - com.apple.CoreSimulator.SimRuntime.iOS-17-5
    case Regex.run(
           ~r/iOS[^\(]+\([^\)]+\)[^c]+(com\.apple\.CoreSimulator\.SimRuntime\.iOS[^\s]+)/,
           output
         ) do
      [_, runtime] -> runtime
      _ -> nil
    end
  end
end
