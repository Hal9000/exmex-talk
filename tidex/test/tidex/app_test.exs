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
          [
            device: device,
            runner: fake_runner(),
            editor_runner: fn _ -> :ok end,
            browser_runner: fn url -> send(self(), {:browser, url}) end,
            width: 40,
            height: 20,
            keys: :none
          ],
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
    {device, _out} = FakeTerminal.open("z q")
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
    assert app.state.server_state == :up
    assert FakeTerminal.text(out) =~ "server:  up"

    {:cont, _app} = App.step(app, {:command, ref, :line, "listening"})
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
    assert app.state.server_state == :up
    Process.exit(pid2, :kill)
  end

  test "x stops the server" do
    {app, out} = app(server_command: "server")
    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, _, pid}
    assert Process.alive?(pid)

    {:cont, app} = App.step(app, {:key, "x"})
    refute Process.alive?(pid)
    assert app.state.server_state == :down
    assert FakeTerminal.text(out) =~ "server:  down"
  end

  test "b launches the browser url" do
    {app, _out} = app(browser_url: "http://localhost:4000")
    {:cont, _app} = App.step(app, {:key, "b"})
    assert_receive {:browser, "http://localhost:4000"}
  end

  test "e yields to the editor command and redraws" do
    parent = self()
    editor = fn command -> send(parent, {:edited, command}) end
    {app, out} = app(editor_command: "true", editor_runner: editor)

    {:cont, _app} = App.step(app, {:key, "e"})
    assert_receive {:edited, "true"}
    assert FakeTerminal.text(out) =~ "status"
  end

  test "l toggles between dashboard and output layouts" do
    {app, out} = app([])
    assert app.state.layout == :dashboard

    {:cont, app} = App.step(app, {:key, "l"})
    assert app.state.layout == :output
    assert FakeTerminal.text(out) =~ "\e[5;1H┌"

    {:cont, app} = App.step(app, {:key, "l"})
    assert app.state.layout == :dashboard
  end

  test "git snapshots update the status pane" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:git, %{branch: "main", dirty: 4}})
    assert app.state.git == %{branch: "main", dirty: 4}
    output = FakeTerminal.text(out)
    assert output =~ "main"
    assert output =~ "4 dirty"
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

  test "loads test/server/browser/editor from config" do
    config = %Tidex.Config{
      test: "echo tests",
      server: "echo serve",
      browser: "http://example.test",
      editor: "true"
    }

    {app, _out} = app(config: config)
    assert app.state.test_command == "echo tests"
    assert app.state.server_command == "echo serve"
    assert app.state.browser_url == "http://example.test"
    assert app.state.editor_command == "true"
  end
end
