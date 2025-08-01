defmodule Orchard.Device do
  @moduledoc """
  Module for managing physical Apple devices using AXe CLI.
  """

  alias Orchard.{Config, CpuInfo, Downloader}

  defstruct [:name, :udid, :platform, :version, :state, :model]

  @type t :: %__MODULE__{
          name: String.t(),
          udid: String.t(),
          platform: String.t(),
          version: String.t(),
          state: String.t(),
          model: String.t()
        }

  @doc """
  Lists all connected devices.
  
  Returns a list of device structs.
  """
  @spec list() :: {:ok, [t()]} | {:error, String.t()}
  def list do
    if not CpuInfo.supported_platform?() do
      {:error, CpuInfo.unsupported_platform_error()}
    else
      with :ok <- Downloader.ensure_available() do
        case System.cmd(Config.axe_cmd(), ["device", "list", "--json"]) do
          {output, 0} ->
            devices = parse_devices(output)
            {:ok, devices}

          {error, _} ->
            {:error, "Failed to list devices: #{error}"}
        end
      end
    end
  rescue
    _ -> {:error, "Failed to execute AXe command"}
  end

  @doc """
  Finds a device by its identifier (name or UDID).
  """
  @spec find(String.t()) :: {:ok, t()} | {:error, String.t()}
  def find(identifier) do
    case list() do
      {:ok, devices} ->
        device = Enum.find(devices, fn d ->
          d.name == identifier || d.udid == identifier
        end)
        
        if device do
          {:ok, device}
        else
          {:error, "Device not found: #{identifier}"}
        end

      error ->
        error
    end
  end

  @doc """
  Runs a command on the specified device.
  """
  @spec run_command(t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def run_command(%__MODULE__{udid: udid}, command) do
    with :ok <- Downloader.ensure_available() do
      case System.cmd(Config.axe_cmd(), ["device", "exec", "--udid", udid, "--", command]) do
        {output, 0} ->
          {:ok, output}

        {error, _} ->
          {:error, "Failed to run command: #{error}"}
      end
    end
  end

  @doc """
  Installs an app on the device.
  """
  @spec install_app(t(), String.t()) :: :ok | {:error, String.t()}
  def install_app(%__MODULE__{udid: udid}, app_path) do
    with :ok <- Downloader.ensure_available() do
      case System.cmd(Config.axe_cmd(), ["device", "install", "--udid", udid, app_path]) do
        {_, 0} ->
          :ok

        {error, _} ->
          {:error, "Failed to install app: #{error}"}
      end
    end
  end

  @doc """
  Uninstalls an app from the device.
  """
  @spec uninstall_app(t(), String.t()) :: :ok | {:error, String.t()}
  def uninstall_app(%__MODULE__{udid: udid}, bundle_id) do
    with :ok <- Downloader.ensure_available() do
      case System.cmd(Config.axe_cmd(), ["device", "uninstall", "--udid", udid, bundle_id]) do
        {_, 0} ->
          :ok

        {error, _} ->
          {:error, "Failed to uninstall app: #{error}"}
      end
    end
  end

  defp parse_devices(json_output) do
    case Jason.decode(json_output) do
      {:ok, data} ->
        devices = data["result"]["devices"] || []
        Enum.map(devices, &parse_device/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp parse_device(device_data) do
    %__MODULE__{
      name: device_data["name"],
      udid: device_data["identifier"],
      platform: device_data["platform"],
      version: device_data["platformVersion"],
      state: device_data["state"],
      model: device_data["deviceType"]
    }
  end
end