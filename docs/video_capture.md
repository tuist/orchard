# Simulator Video Capture & Streaming

iOS simulators don't provide native real-time video stream APIs. This document explains the available approaches and their trade-offs.

## Available Methods

### 1. Screenshot-based Streaming (Built-in)

Captures screenshots at regular intervals and encodes them into a video stream.

```elixir
{:ok, stream} = Orchard.SimulatorStream.start_screenshot_stream(simulator.udid, 
  output: "/tmp/output.mp4",
  fps: 30,
  duration: 60  # optional, in seconds
)

# Stop the stream
Orchard.SimulatorStream.stop_capture(stream)
```

**Pros:**
- Works with standard Orchard/AXe capabilities
- No additional dependencies
- Can output to files or streaming URLs

**Cons:**
- High CPU usage (capturing 30 screenshots/second)
- Not true real-time (frame timing inconsistencies)
- May impact simulator performance

### 2. Native Video Recording (simctl)

Uses the built-in `xcrun simctl io recordVideo` command.

```elixir
{:ok, recording} = Orchard.SimulatorStream.record_video(simulator.udid, 
  "/tmp/recording.mp4",
  codec: "h264",      # or "hevc"
  display: "internal" # or "external"
)

# Stop recording
Orchard.SimulatorStream.stop_capture(recording)
```

**Pros:**
- Native Apple implementation
- Good quality and performance
- Supports H264 and HEVC codecs

**Cons:**
- File-based only (no real-time streaming)
- Cannot pipe to stdout (Apple removed this feature)
- Must wait for recording to complete

### 3. FFmpeg Window Capture

Uses FFmpeg's AVFoundation to capture the simulator window.

```elixir
{:ok, capture} = Orchard.SimulatorStream.start_window_capture("iPhone 15",
  output: "rtmp://streaming-server/live",
  window_title: "iPhone 15 — iOS 18.0",
  fps: 30
)
```

**Pros:**
- Better performance than screenshot-based
- Can stream to various protocols (RTMP, HLS, etc.)
- Captures actual window content

**Cons:**
- Requires FFmpeg with AVFoundation support
- Need to know exact window title
- May capture other UI elements if they overlap

## True Real-time Streaming Options

### Facebook's idb (iOS Development Bridge)

For production use cases requiring true real-time streaming, Facebook's idb provides direct access to the simulator's IOSurface:

```bash
# Install idb
brew tap facebook/fb
brew install idb-companion

# Stream video
idb video-stream --udid SIMULATOR_UDID | ffmpeg -i - -f flv rtmp://server/live
```

**Integration with Orchard:**
```elixir
# Potential wrapper (not implemented)
defmodule Orchard.IDBStream do
  def start_stream(udid, output) do
    System.cmd("idb", ["video-stream", "--udid", udid])
    |> pipe_to_ffmpeg(output)
  end
end
```

### ScreenCaptureKit (macOS 12.3+)

For modern macOS systems, ScreenCaptureKit provides efficient window capture:

```swift
// Native implementation required
let content = try await SCShareableContent.current
let simulatorApp = content.applications.first { 
  $0.bundleIdentifier == "com.apple.iphonesimulator" 
}
```

This would require creating a native macOS helper tool.

## Performance Comparison

| Method | CPU Usage | Latency | Quality | Real-time |
|--------|-----------|---------|---------|-----------|
| Screenshot-based | High | ~100ms | Good | No |
| simctl record | Low | N/A | Excellent | No |
| FFmpeg window | Medium | ~50ms | Good | Yes* |
| idb | Low | ~10ms | Excellent | Yes |
| ScreenCaptureKit | Very Low | ~5ms | Excellent | Yes |

*With caveats about window capture

## Recommendations

1. **For testing/CI**: Use simctl recording - reliable and good quality
2. **For demos**: Screenshot-based streaming is adequate
3. **For production streaming**: Integrate idb or build ScreenCaptureKit solution
4. **For quick prototypes**: FFmpeg window capture

## Example: Streaming to Web via WebRTC

Since we added Membrane dependencies, here's how you could build a WebRTC streaming pipeline:

```elixir
defmodule MyApp.SimulatorWebRTCPipeline do
  use Membrane.Pipeline
  
  @impl true
  def handle_init(_ctx, opts) do
    # This would require implementing a custom source element
    # that uses one of the capture methods above
    
    children = [
      simulator_source: %MyApp.SimulatorSource{
        udid: opts.udid,
        method: :screenshot  # or :idb if available
      },
      encoder: %Membrane.H264.FFmpeg.Encoder{
        preset: :ultrafast,
        tune: :zerolatency
      },
      webrtc: %Membrane.WebRTC.Sink{
        signaling_url: opts.signaling_url
      }
    ]
    
    {[spec: children], %{}}
  end
end
```

## Limitations & Future Work

1. **Apple's Restrictions**: Apple intentionally removed stdout piping from simctl, indicating they don't want to support real-time streaming use cases
2. **Performance**: Screenshot-based approaches will always have performance limitations
3. **Integration**: Full idb or ScreenCaptureKit integration would require significant additional work

For now, Orchard provides the screenshot-based approach as a pragmatic solution that works with existing capabilities. For production use cases requiring true real-time streaming, we recommend using idb alongside Orchard.