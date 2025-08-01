defmodule OrchardTest do
  use ExUnit.Case
  doctest Orchard

  test "version returns correct version" do
    assert Orchard.version() == "0.1.0"
  end

  describe "application lifecycle" do
    @describetag :integration

    test "application starts successfully and all supervisors are running" do
      # Stop the app if it's already running
      Application.stop(:orchard)
      
      # Start the application
      assert {:ok, _} = Application.ensure_all_started(:orchard)
      
      # Verify the supervisor is running
      assert Process.whereis(Orchard.Supervisor) != nil
      assert Process.whereis(Orchard.SimulatorSupervisor) != nil
      assert Process.whereis(Orchard.SimulatorRegistry) != nil
      
      # Stop the application for cleanup
      Application.stop(:orchard)
      
      # Verify everything stopped
      Process.sleep(100)
      assert Process.whereis(Orchard.Supervisor) == nil
    end
  end
end