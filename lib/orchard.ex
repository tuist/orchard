defmodule Orchard do
  @moduledoc """
  Orchard is an Elixir package for managing Apple devices and simulators.

  It provides a high-level interface for:
  - Listing and managing iOS simulators
  - Interacting with physical Apple devices
  - Running commands on devices and simulators
  - Managing device states

  ## Platform Support

  Orchard only works on macOS, as it requires Apple's developer tools
  for device and simulator management.

  ## Setup

  On first use, Orchard will automatically download the AXe CLI binary.
  You can also manually download it using:

      mix orchard.download

  Alternatively, you can configure a custom AXe path in your config:

      config :orchard,
        axe_path: "/path/to/AXe"
  """

  alias Orchard.CpuInfo

  @doc """
  Returns the version of Orchard.
  """
  def version do
    "0.1.0"
  end

  @doc """
  Checks if the current platform is supported.
  """
  defdelegate supported_platform?, to: CpuInfo

  @doc """
  Returns an error message if the platform is not supported.
  """
  defdelegate unsupported_platform_error, to: CpuInfo
end
