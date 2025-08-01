defmodule Orchard.CpuInfo do
  @moduledoc """
  CPU and OS detection utilities for determining system architecture.
  """

  @doc """
  Returns the operating system type.
  """
  @spec os_type() :: :macos | :linux | :windows | :freebsd | :other
  def os_type do
    case :os.type() do
      {:unix, :darwin} -> :macos
      {:unix, :linux} -> :linux
      {:unix, :freebsd} -> :freebsd
      {:win32, _} -> :windows
      _ -> :other
    end
  end

  @doc """
  Returns the CPU architecture type.
  """
  @spec cpu_type() :: String.t()
  def cpu_type do
    case os_type() do
      os when os in [:macos, :freebsd] ->
        case System.cmd("uname", ["-m"]) do
          {"arm64\n", 0} -> "arm64"
          {"aarch64\n", 0} -> "arm64"
          {"x86_64\n", 0} -> "x86_64"
          _ -> fallback_cpu_type()
        end

      _ ->
        fallback_cpu_type()
    end
  end

  defp fallback_cpu_type do
    :erlang.system_info(:system_architecture)
    |> List.to_string()
    |> String.split("-")
    |> case do
      ["arm64" | _] -> "arm64"
      ["aarch64" | _] -> "arm64"
      ["x86_64" | _] -> "x86_64"
      ["i686" | _] -> "x86"
      ["i386" | _] -> "x86"
      ["amd64" | _] -> "x86_64"
      [other | _] -> other
    end
  end

  @doc """
  Checks if the current platform is supported for Apple device management.
  """
  @spec supported_platform?() :: boolean()
  def supported_platform? do
    os_type() == :macos
  end

  @doc """
  Returns a descriptive error message for unsupported platforms.
  """
  @spec unsupported_platform_error() :: String.t()
  def unsupported_platform_error do
    case os_type() do
      :linux -> "Orchard is not supported on Linux. Apple device management requires macOS."
      :windows -> "Orchard is not supported on Windows. Apple device management requires macOS."
      :freebsd -> "Orchard is not supported on FreeBSD. Apple device management requires macOS."
      _ -> "Orchard is only supported on macOS."
    end
  end

  @doc """
  Returns the architecture string for AXe binary downloads.
  """
  @spec axe_arch() :: String.t() | nil
  def axe_arch do
    case {os_type(), cpu_type()} do
      {:macos, "arm64"} -> "macOS-arm64"
      {:macos, "x86_64"} -> "macOS-x86_64"
      _ -> nil
    end
  end
end