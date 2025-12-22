defmodule Orchard.SimulatorStream do
  @moduledoc """
  Provides video capture capabilities for iOS simulators.

  This module provides multiple approaches for video capture:

  1. **AXe stream-video** (v1.1.0+): Native video streaming at 1-30 FPS with multiple
     output formats (MJPEG, raw JPEG, ffmpeg-compatible, BGRA).

  2. **AXe record-video** (v1.1.0+): Direct MP4 recording with H.264 encoding.

  3. **Screenshot-based streaming**: Captures screenshots at intervals and encodes
     them into a video stream. Legacy fallback approach.

  4. **Window capture via FFmpeg**: Uses FFmpeg's AVFoundation to capture the
     simulator window directly.

  The AXe-based methods are recommended for better performance and reliability.
  """

  require Logger

  alias Orchard.{Config, Downloader}

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
  Starts video streaming using AXe's stream-video command.

  Available since AXe 1.1.0. This provides native video streaming with multiple
  output formats and better performance than screenshot-based approaches.

  ## Options

  - `:fps` - Frames per second, 1-30 (default: 10)
  - `:format` - Output format: `:mjpeg`, `:raw`, `:ffmpeg`, `:bgra` (default: `:mjpeg`)
  - `:output` - Output file path or stream destination (default: streams to stdout)

  ## Formats

  - `:mjpeg` - MJPEG format, suitable for direct playback
  - `:raw` - Raw JPEG frames
  - `:ffmpeg` - FFmpeg-compatible output for piping to ffmpeg
  - `:bgra` - Legacy BGRA pixel format

  ## Examples

      # Stream to file in MJPEG format
      {:ok, stream} = Orchard.SimulatorStream.start_axe_stream(udid, fps: 15, output: "stream.mjpeg")

      # Stream for FFmpeg processing
      {:ok, stream} = Orchard.SimulatorStream.start_axe_stream(udid, format: :ffmpeg, fps: 30)

      # Stop the stream
      Orchard.SimulatorStream.stop_capture(stream)
  """
  def start_axe_stream(simulator_udid, opts \\ []) do
    with :ok <- Downloader.ensure_available() do
      fps = Keyword.get(opts, :fps, 10)
      format = Keyword.get(opts, :format, :mjpeg)
      output = Keyword.get(opts, :output)

      format_str =
        case format do
          :mjpeg -> "mjpeg"
          :raw -> "raw"
          :ffmpeg -> "ffmpeg"
          :bgra -> "bgra"
          other -> to_string(other)
        end

      args = [
        "stream-video",
        "--udid",
        simulator_udid,
        "--fps",
        to_string(fps),
        "--format",
        format_str
      ]

      if output do
        # Start as daemon writing to file
        port =
          Port.open({:spawn_executable, Config.axe_cmd()}, [
            {:args, args},
            :binary,
            :exit_status,
            {:line, 65_536}
          ])

        output_file = File.open!(output, [:write, :binary])

        # Start a task to read from port and write to file
        task =
          Task.async(fn ->
            stream_to_file(port, output_file)
          end)

        {:ok,
         %{port: port, task: task, output: output, output_file: output_file, method: :axe_stream}}
      else
        # Start as daemon for raw output
        case MuonTrap.Daemon.start_link(Config.axe_cmd(), args) do
          {:ok, pid} ->
            {:ok, %{pid: pid, method: :axe_stream}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Records video directly to MP4 using AXe's record-video command.

  Available since AXe 1.1.0. This provides direct H.264 encoding to MP4 files
  with configurable quality and scaling options.

  ## Options

  - `:fps` - Frames per second (default: 15)
  - `:quality` - JPEG quality 1-100 (default: system default)
  - `:scale` - Scale factor 0.0-1.0 (default: 1.0, full resolution)

  ## Examples

      # Start recording
      {:ok, recording} = Orchard.SimulatorStream.start_axe_recording(udid, "output.mp4", fps: 20)

      # Record with reduced quality for smaller file size
      {:ok, recording} = Orchard.SimulatorStream.start_axe_recording(udid, "output.mp4",
        fps: 10, quality: 60, scale: 0.5)

      # Stop recording
      Orchard.SimulatorStream.stop_capture(recording)
  """
  def start_axe_recording(simulator_udid, output_path, opts \\ []) do
    with :ok <- Downloader.ensure_available() do
      fps = Keyword.get(opts, :fps, 15)

      args = [
        "record-video",
        "--udid",
        simulator_udid,
        "--fps",
        to_string(fps),
        "--output",
        output_path
      ]

      args =
        if quality = Keyword.get(opts, :quality) do
          args ++ ["--quality", to_string(quality)]
        else
          args
        end

      args =
        if scale = Keyword.get(opts, :scale) do
          args ++ ["--scale", to_string(scale)]
        else
          args
        end

      case MuonTrap.Daemon.start_link(Config.axe_cmd(), args) do
        {:ok, pid} ->
          {:ok, %{pid: pid, output: output_path, method: :axe_record}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Stops a video capture/recording process.
  """
  def stop_capture(%{port: port, output_file: output_file} = capture) when is_port(port) do
    Port.close(port)

    if output_file do
      File.close(output_file)
    end

    if task = Map.get(capture, :task) do
      Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

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

  defp stream_to_file(port, output_file) do
    receive do
      {^port, {:data, {:eol, data}}} ->
        IO.binwrite(output_file, data)
        IO.binwrite(output_file, "\n")
        stream_to_file(port, output_file)

      {^port, {:data, {:noeol, data}}} ->
        IO.binwrite(output_file, data)
        stream_to_file(port, output_file)

      {^port, {:data, data}} when is_binary(data) ->
        IO.binwrite(output_file, data)
        stream_to_file(port, output_file)

      {^port, {:exit_status, _status}} ->
        File.close(output_file)
        :ok

      {^port, :closed} ->
        File.close(output_file)
        :ok
    end
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
