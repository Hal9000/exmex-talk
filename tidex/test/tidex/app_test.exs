defmodule Tidex.AppTest do
  use ExUnit.Case, async: true

  alias Tidex.{App, FakeTerminal}

  test "q quits without running a command" do
    {device, out} = FakeTerminal.open("q")
    runner = fn _cmd -> flunk("command should not run on quit") end

    assert :ok = App.start(device: device, runner: runner)
    output = FakeTerminal.text(out)

    assert output =~ "Tidex"
    assert output =~ "tidex stopped"
    refute output =~ "hello from tidex"
  end

  test "t runs the injected command and shows its output before q quits" do
    {device, out} = FakeTerminal.open("tq")
    runner = fn "echo hello from tidex" -> {"hello from tidex\n", 0} end

    assert :ok = App.start(device: device, runner: runner)
    output = FakeTerminal.text(out)

    assert output =~ "hello from tidex"
    assert output =~ "tidex stopped"
  end

  test "t runs a real hardcoded external command" do
    {device, out} = FakeTerminal.open("tq")

    assert :ok =
             App.start(
               device: device,
               command: "echo hello from tidex"
             )

    assert FakeTerminal.text(out) =~ "hello from tidex"
  end

  test "failed commands still capture output" do
    {device, out} = FakeTerminal.open("tq")

    assert :ok =
             App.start(
               device: device,
               command: "echo boom >&2; exit 7"
             )

    output = FakeTerminal.text(out)
    assert output =~ "boom"
  end

  test "unknown keys are ignored" do
    {device, _out} = FakeTerminal.open("x q")
    runner = fn _cmd -> flunk("unknown keys should not run the command") end

    assert :ok = App.start(device: device, runner: runner)
  end

  test "handle_key q returns quit" do
    app = App.new()
    assert {:quit, ^app} = App.handle_key(app, "q")
  end

  test "handle_key t stores command output on the app" do
    runner = fn cmd ->
      assert cmd == "echo hello from tidex"
      {"captured\n", 0}
    end

    app = App.new(runner: runner)
    assert {:cont, updated} = App.handle_key(app, "t")
    assert updated.state.command_output == "captured\n"
    assert updated.state.last_status == 0
  end
end
