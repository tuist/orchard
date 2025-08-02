# Example: Video Capture from iOS Simulator using Orchard

# Start by finding an available simulator
{:ok, simulators} = Orchard.Simulator.list()
simulator = Enum.find(simulators, fn sim -> sim.state == "Booted" end)

if simulator do
  IO.puts("Using simulator: #{simulator.name} (#{simulator.udid})")
  
  # Method 1: Screenshot-based video capture (can stream)
  IO.puts("\n1. Screenshot-based capture:")
  {:ok, capture} = Orchard.Simulator.capture_video(simulator, 
    output: "/tmp/capture.mp4",
    fps: 30,
    duration: 10
  )
  IO.puts("✓ Capturing for 10 seconds...")
  Process.sleep(10_000)
  
  # Method 2: Native simctl recording (better quality, file only)
  IO.puts("\n2. Native recording:")
  {:ok, recording} = Orchard.Simulator.record_video(simulator, "/tmp/recording.mp4")
  IO.puts("✓ Recording for 5 seconds...")
  Process.sleep(5_000)
  Orchard.Simulator.stop_recording(recording)
  IO.puts("✓ Recording saved to /tmp/recording.mp4")
  
  # For real-time streaming to RTMP server
  IO.puts("\n3. Streaming to RTMP:")
  {:ok, stream} = Orchard.Simulator.capture_video(simulator,
    output: "rtmp://localhost/live/stream",
    fps: 30
  )
  IO.puts("✓ Streaming started to rtmp://localhost/live/stream")
  Process.sleep(5_000)
  Orchard.Simulator.stop_video_capture(stream)
  
else
  IO.puts("No booted simulator found. Please boot a simulator first:")
  IO.puts("  {:ok, sim} = Orchard.Simulator.boot(\"iPhone 15\")")
end

# Note: For production real-time streaming, consider using Facebook's idb:
IO.puts("\nFor true real-time streaming, install and use idb:")
IO.puts("  brew tap facebook/fb && brew install idb-companion")
IO.puts("  idb video-stream --udid #{simulator && simulator.udid}")