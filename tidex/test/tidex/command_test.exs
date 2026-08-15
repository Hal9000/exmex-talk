defmodule Tidex.CommandTest do
  use ExUnit.Case, async: true

  alias Tidex.{Command, FakeTerminal}

  test "streams lines and an exit status to the notify process" do
    ref = make_ref()
    assert {:ok, pid} = Command.start("printf 'one\\ntwo\\n'", self(), ref: ref)

    assert_receive {:command, ^ref, :line, "one"}, 1000
    assert_receive {:command, ^ref, :line, "two"}, 1000
    assert_receive {:command, ^ref, :exit, 0}, 1000
    refute Process.alive?(pid)
  end

  test "failed commands still stream stderr and a non-zero status" do
    ref = make_ref()
    assert {:ok, _} = Command.start("echo boom >&2; exit 7", self(), ref: ref)

    assert_receive {:command, _ref, :line, "boom"}, 1000
    assert_receive {:command, _ref, :exit, 7}, 1000
  end

  test "t runs a real test command and streams output into Tidex" do
    {ui, _device, out} =
      FakeTerminal.start_ui(test_command: "sh -c 'echo one; echo two; echo three'")

    send(ui, {:termex, :key, "t"})

    FakeTerminal.wait_until(fn ->
      FakeTerminal.visible(out) =~ "- pass  0 fail"
    end)

    visible = FakeTerminal.visible(out)
    refute visible =~ "one"
    refute visible =~ "two"
    refute visible =~ "three"
    assert visible =~ "- pass  0 fail"

    send(ui, {:termex, :key, "q"})
    FakeTerminal.wait_until(fn -> not Process.alive?(ui) end)
    assert FakeTerminal.text(out) =~ "tidex stopped"
  end

  test "a failing real test command marks tests as fail" do
    {ui, _device, out} = FakeTerminal.start_ui(test_command: "sh -c 'echo boom; exit 1'")

    send(ui, {:termex, :key, "t"})
    FakeTerminal.wait_until(fn -> FakeTerminal.visible(out) =~ "t  fail" end)
    visible = FakeTerminal.visible(out)
    refute visible =~ "boom"
    assert visible =~ "t  fail"

    send(ui, {:termex, :key, "q"})
    FakeTerminal.wait_until(fn -> not Process.alive?(ui) end)
  end
end
