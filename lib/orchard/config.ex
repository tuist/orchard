defmodule Orchard.Config do
  @moduledoc """
  Configuration module for managing AXe binary versions and paths.
  """

  alias Orchard.CpuInfo

  @external_resource "priv/axe/versions.json"
  @versions File.read!("priv/axe/versions.json") |> Jason.decode!()

  @default_version "1.0.0"

  @doc """
  Returns the default AXe version.
  """
  @spec default_version() :: String.t()
  def default_version, do: @default_version

  @doc """
  Returns all available AXe versions.
  """
  @spec available_versions() :: [String.t()]
  def available_versions do
    Map.keys(@versions) |> Enum.sort()
  end

  @doc """
  Returns the configured AXe version from application config or default.
  """
  @spec configured_version() :: String.t()
  def configured_version do
    Application.get_env(:orchard, :axe_version, @default_version)
  end

  @doc """
  Returns the configured AXe path from application config or nil.
  """
  @spec configured_path() :: String.t() | nil
  def configured_path do
    Application.get_env(:orchard, :axe_path)
  end

  @doc """
  Returns the architecture string for the current system.
  """
  @spec architecture() :: String.t() | nil
  def architecture do
    CpuInfo.axe_arch()
  end

  @doc """
  Returns the path where the AXe binary should be stored.
  """
  @spec executable_path(String.t() | nil) :: String.t()
  def executable_path(version \\ nil) do
    version = version || configured_version()
    arch = architecture()

    if arch do
      Application.app_dir(:orchard, "priv/axe/#{arch}/#{version}/AXe")
    else
      raise "Unsupported architecture for AXe"
    end
  end

  @doc """
  Returns the download URL for a specific version and architecture.
  """
  @spec download_url(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def download_url(version, arch) do
    case get_in(@versions, [version, arch, "url"]) do
      nil -> {:error, "No download URL found for version #{version} on #{arch}"}
      url -> {:ok, url}
    end
  end

  @doc """
  Returns the checksum for a specific version and architecture.
  """
  @spec checksum(String.t(), String.t()) :: String.t() | nil
  def checksum(version, arch) do
    get_in(@versions, [version, arch, "checksum"])
  end

  @doc """
  Checks if a specific version is available.
  """
  @spec version_available?(String.t()) :: boolean()
  def version_available?(version) do
    Map.has_key?(@versions, version)
  end

  @doc """
  Returns the AXe executable command.
  If a custom path is configured, uses that. Otherwise uses the downloaded binary.
  """
  @spec axe_cmd() :: String.t()
  def axe_cmd do
    configured_path() || executable_path()
  end

  @doc """
  Checks if the AXe binary exists at the expected location.
  """
  @spec axe_exists?() :: boolean()
  def axe_exists? do
    File.exists?(axe_cmd())
  end
end
