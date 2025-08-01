defmodule Orchard.Downloader do
  @moduledoc """
  Downloads and manages AXe CLI binaries.
  """

  alias Orchard.{Config, CpuInfo}

  require Logger

  @doc """
  Downloads the AXe binary for the current architecture.
  """
  @spec download(keyword()) :: :ok | {:error, String.t()}
  def download(opts \\ []) do
    if CpuInfo.supported_platform?() do
      version = Keyword.get(opts, :version, Config.configured_version())
      force = Keyword.get(opts, :force, false)

      with {:ok, arch} <- get_architecture(),
           {:ok, url} <- Config.download_url(version, arch),
           :ok <- ensure_not_exists_or_force(version, force),
           {:ok, tmp_file} <- download_file(url),
           :ok <- extract_and_install(tmp_file, version, arch) do
        Logger.info("Successfully downloaded AXe #{version} for #{arch}")
        :ok
      else
        {:error, :already_exists} ->
          Logger.info("AXe #{version} already exists. Use force: true to re-download.")
          :ok

        {:error, reason} = error ->
          Logger.error("Failed to download AXe: #{reason}")
          error
      end
    else
      {:error, CpuInfo.unsupported_platform_error()}
    end
  end

  @doc """
  Checks if AXe is available (either configured path or downloaded).
  """
  @spec ensure_available() :: :ok | {:error, String.t()}
  def ensure_available do
    cond do
      Config.configured_path() && File.exists?(Config.configured_path()) ->
        :ok

      Config.axe_exists?() ->
        :ok

      true ->
        Logger.info("AXe not found. Downloading...")
        download()
    end
  end

  defp get_architecture do
    case Config.architecture() do
      nil -> {:error, CpuInfo.unsupported_platform_error()}
      arch -> {:ok, arch}
    end
  end

  defp ensure_not_exists_or_force(version, force) do
    path = Config.executable_path(version)

    if File.exists?(path) && !force do
      {:error, :already_exists}
    else
      :ok
    end
  end

  defp download_file(url) do
    tmp_dir = System.tmp_dir!()
    tmp_file = Path.join(tmp_dir, "axe-download-#{:erlang.unique_integer([:positive])}.tar.gz")

    Logger.info("Downloading AXe from #{url}...")

    case download_with_httpc(url, tmp_file) do
      :ok -> {:ok, tmp_file}
      error -> error
    end
  end

  defp download_with_httpc(url, dest_file) do
    :inets.start()
    :ssl.start()

    request = {String.to_charlist(url), []}
    http_options = [timeout: 300_000, autoredirect: true]
    options = [stream: String.to_charlist(dest_file)]

    case :httpc.request(:get, request, http_options, options) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_, 200, _}, _, _}} ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        File.rm(dest_file)
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        File.rm(dest_file)
        {:error, "Download failed: #{inspect(reason)}"}
    end
  end

  defp extract_and_install(tar_file, version, _arch) do
    target_dir = Path.dirname(Config.executable_path(version))
    File.mkdir_p!(target_dir)

    Logger.info("Extracting AXe to #{target_dir}...")

    # Create a temp directory for extraction
    tmp_extract_dir =
      Path.join(System.tmp_dir!(), "axe-extract-#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(tmp_extract_dir)

    # Extract the tar.gz file
    case System.cmd("tar", ["-xzf", tar_file, "-C", tmp_extract_dir]) do
      {_, 0} ->
        File.rm(tar_file)
        process_extracted_files(tmp_extract_dir, target_dir, version)

      {error, _} ->
        File.rm(tar_file)
        File.rm_rf!(tmp_extract_dir)
        {:error, "Failed to extract archive: #{error}"}
    end
  rescue
    e ->
      File.rm(tar_file)
      {:error, "Extraction failed: #{inspect(e)}"}
  end

  defp process_extracted_files(tmp_extract_dir, target_dir, version) do
    # Find the axe binary in the extracted contents
    axe_source = find_axe_binary(tmp_extract_dir)

    if axe_source do
      install_binary_and_frameworks(axe_source, target_dir, version)
      File.rm_rf!(tmp_extract_dir)
      :ok
    else
      File.rm_rf!(tmp_extract_dir)
      {:error, "AXe binary not found in archive"}
    end
  end

  defp install_binary_and_frameworks(axe_source, target_dir, version) do
    # Copy the binary to the target location
    axe_target = Config.executable_path(version)
    File.cp!(axe_source, axe_target)

    # Copy frameworks if they exist
    frameworks_source = Path.join(Path.dirname(axe_source), "Frameworks")

    if File.exists?(frameworks_source) do
      frameworks_target = Path.join(target_dir, "Frameworks")
      File.cp_r!(frameworks_source, frameworks_target)
    end

    # Make executable
    File.chmod(axe_target, 0o755)
  end

  defp find_axe_binary(dir) do
    # Look for the axe binary in the extracted directory
    Path.wildcard(Path.join([dir, "**", "axe"]))
    |> Enum.find(&File.regular?/1)
  end
end
