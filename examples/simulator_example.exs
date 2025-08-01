# Example of using Orchard to manage simulators

# Start the application
{:ok, _} = Application.ensure_all_started(:orchard)

# List all available simulators
{:ok, simulators} = Orchard.Simulator.list()

IO.puts("Available simulators:")
Enum.each(simulators, fn sim ->
  IO.puts("  #{sim.name} (#{sim.udid}) - #{sim.state}")
end)

# Find a specific simulator (e.g., iPhone 16)
iphone = Enum.find(simulators, fn sim -> 
  String.contains?(sim.name, "iPhone 16") && sim.state == "Shutdown"
end)

if iphone do
  IO.puts("\nBooting #{iphone.name}...")
  
  # Boot the simulator - this will start a GenServer to manage it
  case Orchard.Simulator.boot(iphone) do
    {:ok, _} ->
      IO.puts("Successfully booted simulator!")
      
      # The simulator is now managed by a GenServer that will monitor its state
      IO.puts("Simulator server is running and monitoring the device.")
      
      # Wait a bit
      Process.sleep(5000)
      
      # Take a screenshot
      screenshot_path = "/tmp/orchard_screenshot.png"
      case Orchard.Simulator.screenshot(iphone, screenshot_path) do
        :ok ->
          IO.puts("Screenshot saved to #{screenshot_path}")
        {:error, reason} ->
          IO.puts("Failed to take screenshot: #{reason}")
      end
      
      # Shutdown the simulator
      IO.puts("\nShutting down simulator...")
      case Orchard.Simulator.shutdown(iphone) do
        :ok ->
          IO.puts("Simulator shut down successfully")
        {:error, reason} ->
          IO.puts("Failed to shutdown: #{reason}")
      end
      
    {:error, reason} ->
      IO.puts("Failed to boot simulator: #{reason}")
  end
else
  IO.puts("No iPhone 16 simulator found in Shutdown state")
end

# List active simulator servers
IO.puts("\nActive simulator servers:")
active = Orchard.SimulatorSupervisor.list_active_simulators()
Enum.each(active, fn sim ->
  IO.puts("  #{sim.name} (#{sim.udid})")
end)