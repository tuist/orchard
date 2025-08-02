defmodule Orchard.SimulatorStream do
  @moduledoc """
  Provides video capture capabilities for iOS simulators.

  Since iOS simulators don't expose real-time video streams, this module provides
  two approaches:

  1. **Screenshot-based streaming**: Captures screenshots at intervals and encodes
     them into a video stream. Good for basic use cases but has performance limitations.

  2. **Window capture via FFmpeg**: Uses FFmpeg's AVFoundation to capture the
     simulator window directly. Better performance but requires knowing the window title.

  For production use cases requiring true real-time streaming, consider:
  - Facebook's idb tool which can access the simulator's IOSurface
  - Custom ScreenCaptureKit implementation (macOS 12.3+)
  """

  require Logger

  @doc """
  Starts screenshot-based video streaming from a simulator.

  This method captures screenshots at ~30 FPS and pipes them through FFmpeg
  to create an H264 video stream.

  Options:
  - `:output` - Output destination (file path or URL)
  - `:fps` - Frames per second (default: 30)
  - `:duration` - Maximum duration in seconds (optional)
  """
  def start_screenshot_stream(simulator_udid, opts \\ []) do
    output = Keyword.get(opts, :output, "/tmp/simulator_#{simulator_udid}.mp4")
    fps = Keyword.get(opts, :fps, 30)
    duration = Keyword.get(opts, :duration)

    # Build FFmpeg command that reads PNG images from stdin
    ffmpeg_args = [
      "-f",
      "image2pipe",
      "-vcodec",
      "png",
      "-framerate",
      to_string(fps),
      "-i",
      "-",
      "-vcodec",
      "libx264",
      "-preset",
      "ultrafast",
      "-tune",
      "zerolatency",
      "-pix_fmt",
      "yuv420p"
    ]

    ffmpeg_args =
      if duration do
        ffmpeg_args ++ ["-t", to_string(duration)]
      else
        ffmpeg_args
      end

    ffmpeg_args = ffmpeg_args ++ [output]

    # Start FFmpeg process
    port =
      Port.open({:spawn_executable, System.find_executable("ffmpeg")}, [
        {:args, ffmpeg_args},
        :binary,
        :exit_status
      ])

    # Start screenshot capture task
    capture_task =
      Task.async(fn ->
        capture_screenshots(simulator_udid, port, fps)
      end)

    {:ok, %{port: port, task: capture_task, output: output}}
  end

  @doc """
  Starts window-based video capture using FFmpeg's AVFoundation.

  This method captures the simulator window directly, providing better performance
  than screenshot-based capture.

  Options:
  - `:output` - Output destination (file path or URL)
  - `:window_title` - Simulator window title (e.g., "iPhone 15 — iOS 18.0")
  - `:fps` - Frames per second (default: 30)
  - `:duration` - Maximum duration in seconds (optional)
  """
  def start_window_capture(simulator_name, opts \\ []) do
    output = Keyword.get(opts, :output, "/tmp/simulator_window.mp4")
    _window_title = Keyword.get(opts, :window_title, simulator_name)
    fps = Keyword.get(opts, :fps, 30)
    duration = Keyword.get(opts, :duration)

    # First, list available capture devices to find the right display
    {_devices_output, 0} =
      System.cmd(
        "ffmpeg",
        [
          "-f",
          "avfoundation",
          "-list_devices",
          "true",
          "-i",
          ""
        ],
        stderr_to_stdout: true
      )

    # Build FFmpeg command for window capture
    ffmpeg_args = [
      "-f",
      "avfoundation",
      "-framerate",
      to_string(fps),
      "-capture_cursor",
      "0",
      # Capture main display, no audio
      "-i",
      "1:none",
      # You might need to adjust crop settings
      "-vf",
      "crop='iw:ih:0:0'",
      "-vcodec",
      "libx264",
      "-preset",
      "ultrafast",
      "-tune",
      "zerolatency"
    ]

    ffmpeg_args =
      if duration do
        ffmpeg_args ++ ["-t", to_string(duration)]
      else
        ffmpeg_args
      end

    ffmpeg_args = ffmpeg_args ++ [output]

    case System.cmd("ffmpeg", ffmpeg_args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, %{output: output, method: :window_capture}}

      {error, _} ->
        {:error, "FFmpeg window capture failed: #{error}"}
    end
  end

  @doc """
  Records video using simctl (file-based only).

  This is the native iOS simulator recording capability. It records to a file
  and cannot stream in real-time.
  """
  def record_video(simulator_udid, output_path, opts \\ []) do
    codec = Keyword.get(opts, :codec, "h264")
    display = Keyword.get(opts, :display, "internal")
    mask = Keyword.get(opts, :mask, "ignored")
    force = Keyword.get(opts, :force, false)

    args = [
      "simctl",
      "io",
      simulator_udid,
      "recordVideo",
      "--codec",
      codec,
      "--display",
      display,
      "--mask",
      mask
    ]

    args = if force, do: args ++ ["--force"], else: args
    args = args ++ [output_path]

    case MuonTrap.Daemon.start_link("xcrun", args) do
      {:ok, pid} ->
        {:ok, %{pid: pid, output: output_path, method: :simctl_record}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stops a video capture/recording process.
  """
  def stop_capture(%{port: port}) when is_port(port) do
    Port.close(port)
    :ok
  end

  def stop_capture(%{pid: pid}) when is_pid(pid) do
    GenServer.stop(pid)
    :ok
  end

  def stop_capture(%{task: task}) do
    Task.shutdown(task, :brutal_kill)
    :ok
  end

  # Private functions

  defp capture_screenshots(simulator_udid, port, fps) do
    interval = round(1000 / fps)
    capture_loop(simulator_udid, port, interval)
  end

  defp capture_loop(simulator_udid, port, interval) do
    start_time = System.monotonic_time(:millisecond)

    # Capture screenshot to temporary file
    temp_path = "/tmp/sim_screenshot_#{:erlang.unique_integer()}.png"

    case Orchard.Simulator.screenshot(simulator_udid, temp_path) do
      :ok ->
        # Read and send to FFmpeg
        case File.read(temp_path) do
          {:ok, png_data} ->
            Port.command(port, png_data)
            File.rm(temp_path)

          {:error, reason} ->
            Logger.error("Failed to read screenshot: #{reason}")
        end

      {:error, reason} ->
        Logger.error("Failed to capture screenshot: #{reason}")
    end

    # Calculate time to next frame
    elapsed = System.monotonic_time(:millisecond) - start_time
    sleep_time = max(0, interval - elapsed)

    Process.sleep(sleep_time)
    capture_loop(simulator_udid, port, interval)
  end
end
