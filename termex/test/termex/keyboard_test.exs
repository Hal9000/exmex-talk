defmodule Termex.KeyboardTest do
  use ExUnit.Case, async: true

  alias Termex.Capture

  test "forwards each key then eof as messages" do
    {device, _out} = Capture.open("tq")
    assert {:ok, pid} = Termex.keyboard(device, notify: self())

    assert_receive {:termex, :key, "t"}
    assert_receive {:termex, :key, "q"}
    assert_receive {:termex, :key, :eof}
    refute Process.alive?(pid)
  end

  test "forwards decoded arrow keys" do
    {device, _out} = Capture.open("\e[A\e[B")
    assert {:ok, _pid} = Termex.keyboard(device, notify: self())

    assert_receive {:termex, :key, :up}
    assert_receive {:termex, :key, :down}
    assert_receive {:termex, :key, :eof}
  end
end
