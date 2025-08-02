defmodule Orchard.DownloaderTest do
  use ExUnit.Case
  import Bitwise
  alias Orchard.Downloader

  describe "AXe binary download" do
    @describetag :integration

    setup do
      # Clean up any existing download before test
      version = Orchard.Config.configured_version()
      executable_path = Orchard.Config.executable_path(version)

      if File.exists?(executable_path) do
        File.rm_rf!(Path.dirname(executable_path))
      end

      on_exit(fn ->
        # Clean up after test
        if File.exists?(executable_path) do
          File.rm_rf!(Path.dirname(executable_path))
        end
      end)

      :ok
    end

    test "ensures AXe is available and downloads it if needed" do
      # First, verify it's not available
      refute Downloader.available?()

      # Now ensure it's available
      case Downloader.ensure_available() do
        :ok ->
          # Verify it was downloaded
          assert Downloader.available?()

          # Verify the executable exists
          version = Orchard.Config.configured_version()
          executable_path = Orchard.Config.executable_path(version)
          assert File.exists?(executable_path)

          # Verify it's executable
          %{mode: mode} = File.stat!(executable_path)
          assert (mode &&& 0o111) != 0

        {:error, reason} ->
          # Should only fail on non-macOS systems
          assert reason =~ "only supported on macOS"
      end
    end

    test "doesn't re-download if already available" do
      case Downloader.download() do
        :ok ->
          # First download succeeded
          assert Downloader.available?()

          # Second call should not re-download
          assert :ok = Downloader.ensure_available()

        {:error, reason} ->
          # Should only fail on non-macOS systems
          assert reason =~ "only supported on macOS"
      end
    end

    test "force download overwrites existing binary" do
      case Downloader.download() do
        :ok ->
          # First download succeeded
          assert Downloader.available?()

          # Get the original file stats
          version = Orchard.Config.configured_version()
          executable_path = Orchard.Config.executable_path(version)
          original_stat = File.stat!(executable_path)

          # Wait a bit to ensure different timestamp
          Process.sleep(1000)

          # Force re-download
          assert :ok = Downloader.download(force: true)

          # Verify file was replaced (different timestamp)
          new_stat = File.stat!(executable_path)
          assert new_stat.mtime != original_stat.mtime

        {:error, reason} ->
          # Should only fail on non-macOS systems
          assert reason =~ "only supported on macOS"
      end
    end
  end
end
