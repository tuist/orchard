defmodule OrchardTest do
  use ExUnit.Case
  doctest Orchard

  test "version returns correct version" do
    assert Orchard.version() == "0.1.0"
  end
end