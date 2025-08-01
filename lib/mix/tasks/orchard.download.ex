defmodule Mix.Tasks.Orchard.Download do
  use Mix.Task

  @shortdoc "Downloads the AXe CLI binary for the current platform"

  @moduledoc """
  Downloads the AXe CLI binary for managing Apple devices and simulators.

  ## Usage

      mix orchard.download

  ## Options

    * `--version` - Specify the AXe version to download (default: #{Orchard.Config.default_version()})
    * `--force` - Force re-download even if the binary already exists

  ## Examples

      # Download the default version
      mix orchard.download

      # Download a specific version
      mix orchard.download --version 1.0.0

      # Force re-download
      mix orchard.download --force

  ## Configuration

  You can configure the AXe version in your `config.exs`:

      config :orchard,
        axe_version: "1.0.0"

  Or provide a custom path to an existing AXe binary:

      config :orchard,
        axe_path: "/usr/local/bin/AXe"
  """

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:orchard)

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [version: :string, force: :boolean]
      )

    Mix.shell().info("Orchard AXe Downloader")
    Mix.shell().info("====================")

    case Orchard.CpuInfo.supported_platform?() do
      true ->
        do_download(opts)

      false ->
        Mix.shell().error(Orchard.CpuInfo.unsupported_platform_error())
        Mix.raise("Unsupported platform")
    end
  end

  defp do_download(opts) do
    version = opts[:version] || Orchard.Config.configured_version()
    force = opts[:force] || false

    Mix.shell().info("Platform: #{Orchard.CpuInfo.os_type()}")
    Mix.shell().info("Architecture: #{Orchard.CpuInfo.cpu_type()}")
    Mix.shell().info("AXe version: #{version}")

    case Orchard.Downloader.download(version: version, force: force) do
      :ok ->
        Mix.shell().info("")
        Mix.shell().info("✓ AXe successfully downloaded!")
        Mix.shell().info("  Location: #{Orchard.Config.executable_path(version)}")

      {:error, reason} ->
        Mix.shell().error("")
        Mix.shell().error("✗ Download failed: #{reason}")
        Mix.raise("Failed to download AXe")
    end
  end
end
