defmodule Tidex.AppTest do
  use ExUnit.Case, async: true

  alias Tidex.{App, FakeTerminal}

  defp fake_runner(parent \\ self()) do
    fn command, notify, ref ->
      pid = spawn(fn -> Process.sleep(:infinity) end)
      send(parent, {:started, command, notify, ref, pid})
      {:ok, pid}
    end
  end

  defp app(opts) do
    {device, out} = FakeTerminal.open()

    app =
      App.new(
        Keyword.merge(
          [device: device, runner: fake_runner(), width: 40, height: 20, keys: :none],
          opts
        )
      )

    {app, out}
  end

  test "q quits without running a command" do
    {device, out} = FakeTerminal.open("q")
    runner = fn _cmd, _notify, _ref -> flunk("command should not run on quit") end

    assert :ok = App.start(device: device, runner: runner, width: 40, height: 20)
    output = FakeTerminal.text(out)

    assert output =~ "status"
    assert output =~ "tidex stopped"
  end

  test "unknown keys are ignored" do
    {device, _out} = FakeTerminal.open("x q")
    runner = fn _cmd, _notify, _ref -> flunk("unknown keys should not run a command") end

    assert :ok = App.start(device: device, runner: runner, width: 40, height: 20)
  end

  test "handle_event q returns quit" do
    {app, _out} = app([])
    assert {:quit, ^app} = App.handle_event(app, {:key, "q"})
  end

  test "t starts the test command and marks tests running" do
    {app, out} = app(test_command: "mix test")
    assert {:cont, app} = App.step(app, {:key, "t"})

    assert_receive {:started, "mix test", notify, ref, _pid}
    assert notify == self()
    assert app.state.test_state == :running
    assert app.state.test_ref == ref
    assert FakeTerminal.text(out) =~ "tests:   running"
  end

  test "lines appear in the output pane as they arrive" do
    {app, out} = app(test_command: "mix test")
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref

    {:cont, app} = App.step(app, {:command, ref, :line, "one"})
    output = FakeTerminal.text(out)
    assert output =~ "one"
    refute output =~ "two"
    assert app.state.test_state == :running

    {:cont, app} = App.step(app, {:command, ref, :line, "two"})
    output = FakeTerminal.text(out)
    assert output =~ "one"
    assert output =~ "two"

    {:cont, app} = App.step(app, {:command, ref, :exit, 0})
    assert app.state.test_state == :pass
    assert FakeTerminal.text(out) =~ "tests:   pass"
  end

  test "non-zero test exit marks tests as fail" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref
    {:cont, app} = App.step(app, {:command, ref, :exit, 1})

    assert app.state.test_state == :fail
    assert FakeTerminal.text(out) =~ "tests:   fail"
  end

  test "s starts the server and streams into the output pane" do
    {app, out} = app(server_command: "python3 -m http.server 4000")
    {:cont, app} = App.step(app, {:key, "s"})

    assert_receive {:started, "python3 -m http.server 4000", _notify, ref, _pid}
    assert app.state.server_state == :running
    assert FakeTerminal.text(out) =~ "server:  running"

    {:cont, app} = App.step(app, {:command, ref, :line, "listening"})
    assert FakeTerminal.text(out) =~ "listening"
  end

  test "s restarts a running server" do
    parent = self()
    {app, _out} = app(runner: fake_runner(parent), server_command: "server")

    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, _, pid1}
    assert Process.alive?(pid1)

    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, _, pid2}

    refute Process.alive?(pid1)
    assert Process.alive?(pid2)
    assert app.state.server_state == :running
    Process.exit(pid2, :kill)
  end

  test "stale command lines from a previous run are ignored" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    old_ref = app.state.test_ref
    {:cont, app} = App.step(app, {:key, "t"})
    new_ref = app.state.test_ref

    {:cont, app} = App.step(app, {:command, old_ref, :line, "stale"})
    refute FakeTerminal.text(out) =~ "stale"

    {:cont, _app} = App.step(app, {:command, new_ref, :line, "fresh"})
    assert FakeTerminal.text(out) =~ "fresh"
  end
end
