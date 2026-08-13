defmodule TidexTest do
  use ExUnit.Case, async: true

  test "start/1 is the public entry point" do
    {device, _out} = Tidex.FakeTerminal.open("q")
    assert :ok = Tidex.start(device: device)
  end
end
