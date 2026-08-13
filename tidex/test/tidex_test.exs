defmodule TidexTest do
  use ExUnit.Case, async: true

  test "start/1 is the public entry point" do
    {device, _out} = Tidex.FakeTerminal.open("q")
    assert :ok = Tidex.start(device: device, width: 40, height: 20)
  end

  test "default test command prefers mix test in this repo" do
    assert Tidex.App.default_test_command() == "mix test"
  end
end
