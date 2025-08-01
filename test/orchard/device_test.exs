defmodule Orchard.DeviceTest do
  use ExUnit.Case
  alias Orchard.Device

  describe "Device struct" do
    test "creates a device struct with all fields" do
      device = %Device{
        name: "iPhone 15",
        udid: "12345678-1234-1234-1234-123456789012",
        platform: "iOS",
        version: "17.0",
        state: "connected",
        model: "iPhone15,1"
      }

      assert device.name == "iPhone 15"
      assert device.udid == "12345678-1234-1234-1234-123456789012"
      assert device.platform == "iOS"
      assert device.version == "17.0"
      assert device.state == "connected"
      assert device.model == "iPhone15,1"
    end
  end
end
