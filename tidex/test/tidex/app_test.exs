defmodule Tidex.AppTest do
  use ExUnit.Case, async: true

  alias Tidex.{App, FakeTerminal, Layout}

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

  defp output_inner(state) do
    layout = Layout.compute(state)
    Layout.inner(layout.output)
  end

  defp fail_lines(out, app) do
    layout = Layout.compute(app.state)
    FakeTerminal.region_lines(out, Layout.inner(layout.fail))
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

  test "? toggles the help overlay" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "?"})
    assert app.state.overlay == :help
    assert FakeTerminal.last_frame(out) =~ "esc or ? closes"

    {:cont, app} = App.step(app, {:key, "?"})
    assert app.state.overlay == nil
    refute FakeTerminal.last_frame(out) =~ "esc or ? closes"
    assert FakeTerminal.text(out) =~ "esc or ? closes"
  end

  test "esc closes the help overlay" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "?"})
    {:cont, app} = App.handle_event(app, {:key, :esc})
    assert app.state.overlay == nil
  end

  test "command keys are ignored while help is open" do
    {app, _out} = app([])
    runner = fn _cmd, _notify, _ref -> flunk("help should block commands") end
    app = %{app | runner: runner}

    {:cont, app} = App.handle_event(app, {:key, "?"})
    {:cont, app} = App.handle_event(app, {:key, "t"})
    {:cont, app} = App.handle_event(app, {:key, :up})
    assert app.state.overlay == :help
    assert app.state.test_state == :idle
  end

  test "q still quits while help is open" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "?"})
    assert {:quit, ^app} = App.handle_event(app, {:key, "q"})
  end

  test "g toggles the git overlay" do
    git = %{branch: "main", dirty: 1, status: "On branch main\nmodified: lib/tidex.ex"}
    {app, out} = app(git: git)
    {:cont, app} = App.step(app, {:key, "g"})
    assert app.state.overlay == :git
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "On branch main"
    assert FakeTerminal.visible(out) =~ "add -u"

    {:cont, app} = App.step(app, {:key, "g"})
    assert app.state.overlay == nil
    refute FakeTerminal.visible(out) =~ "add -u"
    assert Termex.ANSI.strip(FakeTerminal.text(out)) =~ "add -u"
  end

  test "esc closes the git overlay" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "g"})
    {:cont, app} = App.handle_event(app, {:key, :esc})
    assert app.state.overlay == nil
  end

  test "a from the git overlay runs git add -u" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "g"})
    {:cont, app} = App.step(app, {:key, "a"})

    assert_receive {:started, "git add -u", _notify, ref, _pid}
    assert app.state.overlay == nil
    assert app.state.output_source == :git
    assert app.state.git_cmd_ref == ref

    {:cont, app} = App.step(app, {:command, ref, :line, "staged"})
    assert FakeTerminal.region_lines(out, output_inner(app.state)) == ["staged"]
  end

  test "p from the git overlay runs git push" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "g"})
    {:cont, app} = App.handle_event(app, {:key, "p"})
    assert_receive {:started, "git push", _, _, _}
    assert app.state.overlay == nil
  end

  test "c from the git overlay yields git commit" do
    parent = self()
    editor = fn command -> send(parent, {:edited, command}) end
    {app, _out} = app(editor_runner: editor, git_reader: fn -> %{branch: "main", dirty: 0} end)

    {:cont, app} = App.step(app, {:key, "g"})
    {:cont, app} = App.step(app, {:key, "c"})
    assert_receive {:edited, "git commit"}
    assert app.state.overlay == nil
    assert app.state.git.status == ""
  end

  test "a does nothing unless the git overlay is open" do
    {app, _out} = app([])
    runner = fn _cmd, _notify, _ref -> flunk("add should not run") end
    app = %{app | runner: runner}
    {:cont, app} = App.handle_event(app, {:key, "a"})
    assert app.state.git_cmd_ref == nil
  end

  test "up pins the output pane one line above the tail" do
    {app, _out} = app([])
    lines = Enum.map(1..15, &"row#{&1}")
    app = %{app | state: %{app.state | output_lines: lines}}

    {:cont, app} = App.handle_event(app, {:key, :up})
    assert app.state.output_scroll == 4
  end

  test "down at the tail stays in follow mode" do
    {app, _out} = app([])
    lines = Enum.map(1..15, &"row#{&1}")
    app = %{app | state: %{app.state | output_lines: lines, output_scroll: :follow}}

    {:cont, app} = App.handle_event(app, {:key, :down})
    assert app.state.output_scroll == :follow
  end

  test "page up jumps to the top of the log" do
    {app, _out} = app([])
    lines = Enum.map(1..15, &"row#{&1}")
    app = %{app | state: %{app.state | output_lines: lines}}

    {:cont, app} = App.handle_event(app, {:key, :page_up})
    assert app.state.output_scroll == 0
  end

  test "a later frame drops tail lines that scrolled out of the output pane" do
    {app, out} = app(width: 40, height: 12)
    lines = Enum.map(1..20, &"row#{&1}-end")
    app = %{app | state: %{app.state | output_lines: lines}}

    {:cont, app} = App.step(app, {:key, :down})
    inner = output_inner(app.state)
    assert FakeTerminal.region_lines(out, inner) == ["row19-end", "row20-end"]

    app = %{app | state: %{app.state | output_scroll: 0}}
    {:cont, _app} = App.step(app, {:key, :left})
    visible = FakeTerminal.region_lines(out, inner)
    assert visible == ["row1-end", "row2-end"]
    refute "row20-end" in visible
    assert length(visible) == inner.height
    assert FakeTerminal.text(out) =~ "row20-end"
  end

  test "new lines while pinned leave the window in place" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref

    lines = Enum.map(1..15, &"row#{&1}")
    app = %{app | state: %{app.state | output_lines: lines, output_scroll: 0}}

    {:cont, app} = App.step(app, {:command, ref, :line, "newest"})
    assert app.state.output_scroll == 0
    assert List.last(app.state.output_lines) == "newest"

    visible = FakeTerminal.region_lines(out, output_inner(app.state))
    assert hd(visible) == "row1"
    refute "newest" in visible
  end

  test "new lines while following stay on the tail" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref
    lines = Enum.map(1..15, &"row#{&1}")
    app = %{app | state: %{app.state | output_lines: lines, output_scroll: :follow}}

    {:cont, app} = App.step(app, {:command, ref, :line, "newest"})
    assert app.state.output_scroll == :follow
    visible = FakeTerminal.region_lines(out, output_inner(app.state))
    assert List.last(visible) == "newest"
  end

  test "running tests again resets scroll to follow" do
    {app, _out} = app([])
    app = %{app | state: %{app.state | output_scroll: 3, output_lines: ["old"]}}

    {:cont, app} = App.step(app, {:key, "t"})
    assert app.state.output_scroll == :follow
    assert app.state.output_lines == []
    assert app.state.failures == []
  end

  test "left and right do not scroll" do
    {app, _out} = app([])
    app = %{app | state: %{app.state | output_lines: Enum.map(1..15, &"row#{&1}")}}

    {:cont, app} = App.handle_event(app, {:key, :left})
    {:cont, app} = App.handle_event(app, {:key, :right})
    assert app.state.output_scroll == :follow
  end

  @exunit_fail [
    "  1) test Foo.bar/1 (FooTest)",
    "     test/foo_test.exs:12",
    "     Assertion with == failed",
    "  2) test boom (FooTest)",
    "     test/foo_test.exs:20",
    "     ** (RuntimeError) timed out"
  ]

  test "a failing test run fills the fail strip and left/right cycle it" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref
    app = %{app | state: %{app.state | output_lines: @exunit_fail}}

    {:cont, app} = App.step(app, {:command, ref, :exit, 1})
    assert app.state.test_state == :fail
    assert length(app.state.failures) == 2
    assert FakeTerminal.last_frame(out) =~ "fail 1/2"
    assert fail_lines(out, app) |> Enum.any?(&(&1 =~ "Foo.bar"))

    {:cont, app} = App.step(app, {:key, :right})
    visible = fail_lines(out, app)
    assert FakeTerminal.last_frame(out) =~ "fail 2/2"
    assert Enum.any?(visible, &(&1 =~ "test boom"))
    refute Enum.any?(visible, &(&1 =~ "Foo.bar"))

    {:cont, _app} = App.step(app, {:key, :left})
    assert FakeTerminal.last_frame(out) =~ "fail 1/2"
  end

  test "a passing run clears parsed failures" do
    {app, _out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref
    app = %{app | state: %{app.state | output_lines: @exunit_fail, failures: [%{name: "old"}]}}

    {:cont, app} = App.step(app, {:command, ref, :exit, 0})
    assert app.state.test_state == :pass
    assert app.state.failures == []
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
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "tests:   running"
    refute frame =~ "tests:   idle"
  end

  test "lines appear in the output pane as they arrive" do
    {app, out} = app(test_command: "mix test")
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref

    {:cont, app} = App.step(app, {:command, ref, :line, "one"})
    visible = FakeTerminal.region_lines(out, output_inner(app.state))
    assert visible == ["one"]
    refute "two" in visible
    assert app.state.test_state == :running

    {:cont, app} = App.step(app, {:command, ref, :line, "two"})
    assert FakeTerminal.region_lines(out, output_inner(app.state)) == ["one", "two"]

    {:cont, app} = App.step(app, {:command, ref, :exit, 0})
    assert app.state.test_state == :pass
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "tests:   pass"
    refute frame =~ "tests:   running"
  end

  test "non-zero test exit marks tests as fail" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref
    {:cont, app} = App.step(app, {:command, ref, :exit, 1})

    assert app.state.test_state == :fail
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "tests:   fail"
    refute frame =~ "tests:   running"
  end

  test "s starts the server and streams into the output pane" do
    {app, out} = app(server_command: "python3 -m http.server 4000")
    {:cont, app} = App.step(app, {:key, "s"})

    assert_receive {:started, "python3 -m http.server 4000", _notify, ref, _pid}
    assert app.state.server_state == :up
    assert FakeTerminal.text(out) =~ "server:  up"

    {:cont, _app} = App.step(app, {:command, ref, :line, "listening"})
    assert FakeTerminal.region_lines(out, output_inner(app.state)) == ["listening"]
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
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "server:  down"
    refute frame =~ "server:  up"
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

  test "e opens the current failure at line for a known editor" do
    parent = self()
    editor = fn command -> send(parent, {:edited, command}) end

    {app, _out} = app(editor_command: "nvim", editor_runner: editor)

    app = %{
      app
      | state: %{
          app.state
          | failures: [
              %{name: "one", file: "test/a.exs", line: 3, snippet: ""},
              %{name: "two", file: "test/b.exs", line: 9, snippet: ""}
            ],
            failure_index: 1
        }
    }

    {:cont, _app} = App.step(app, {:key, "e"})
    assert_receive {:edited, "nvim +9 'test/b.exs'"}
  end

  test "l toggles between dashboard and output layouts" do
    {app, out} = app([])
    assert app.state.layout == :dashboard

    {:cont, app} = App.step(app, {:key, "l"})
    assert app.state.layout == :output
    assert FakeTerminal.last_frame(out) =~ "\e[5;1H┌"

    {:cont, app} = App.step(app, {:key, "l"})
    assert app.state.layout == :dashboard
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "\e[7;1H┌"
    refute frame =~ "\e[5;1H┌"
  end

  test "git snapshots update the status pane" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:git, %{branch: "main", dirty: 4}})
    assert app.state.git == %{branch: "main", dirty: 4, status: ""}
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "main"
    assert frame =~ "4 dirty"
  end

  test "stale command lines from a previous run are ignored" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    old_ref = app.state.test_ref
    {:cont, app} = App.step(app, {:key, "t"})
    new_ref = app.state.test_ref

    {:cont, app} = App.step(app, {:command, old_ref, :line, "stale"})
    refute FakeTerminal.text(out) =~ "stale"
    refute "stale" in FakeTerminal.region_lines(out, output_inner(app.state))

    {:cont, _app} = App.step(app, {:command, new_ref, :line, "fresh"})
    assert FakeTerminal.region_lines(out, output_inner(app.state)) == ["fresh"]
  end

  test "server process exit marks the server down" do
    {app, out} = app(server_command: "server")
    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, ref, _pid}

    {:cont, app} = App.step(app, {:command, ref, :exit, 1})
    assert app.state.server_state == :down
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "server:  down"
    refute frame =~ "server:  up"
  end

  test "editor stops the current keyboard and starts a new one" do
    {device, _out} = FakeTerminal.open("xxxx")
    {:ok, pid1} = Tidex.Keyboard.start(device, self())
    parent = self()

    {app, _captured} =
      app(
        device: device,
        keys: :device,
        editor_command: "true",
        editor_runner: fn _ -> send(parent, {:during_edit, Process.alive?(pid1)}) end
      )

    app = %{app | keyboard: pid1}
    {:cont, app} = App.step(app, {:key, "e"})

    assert_receive {:during_edit, false}
    assert is_pid(app.keyboard)
    assert app.keyboard != pid1
    Tidex.Keyboard.stop(app.keyboard)
  end

  test "loads project/test/server/browser/editor from config" do
    config = %Tidex.Config{
      project: "demo",
      test: "echo tests",
      server: "echo serve",
      browser: "http://example.test",
      editor: "true"
    }

    {app, _out} = app(config: config)
    assert app.state.project_name == "demo"
    assert app.state.test_command == "echo tests"
    assert app.state.server_command == "echo serve"
    assert app.state.browser_url == "http://example.test"
    assert app.state.editor_command == "true"
  end

  test "missing tidex.conf opens a setup overlay" do
    dir = tmp_dir()

    try do
      {app, out} = app(cwd: dir, width: 80)
      assert app.state.overlay == :setup
      assert app.state.setup.offer_cwd
      {:cont, app} = App.step(app, {:key, "z"})
      assert FakeTerminal.last_frame(out) =~ "no tidex.conf"
      assert FakeTerminal.last_frame(out) =~ "write in cwd"
      assert app.state.overlay == :setup
    after
      File.rm_rf!(dir)
    end
  end

  test "y writes tidex.conf in cwd and closes setup" do
    dir = tmp_dir()

    try do
      {app, _out} = app(cwd: dir)
      {:cont, app} = App.step(app, {:key, "y"})
      assert app.state.overlay == nil
      assert File.exists?(Path.join(dir, "tidex.conf"))
      assert app.state.project_name == Path.basename(dir)
      body = File.read!(Path.join(dir, "tidex.conf"))
      refute body =~ ~r/^editor:/m
    after
      File.rm_rf!(dir)
    end
  end

  test "n skips writing and closes setup" do
    dir = tmp_dir()

    try do
      {app, _out} = app(cwd: dir)
      {:cont, app} = App.step(app, {:key, "n"})
      assert app.state.overlay == nil
      refute File.exists?(Path.join(dir, "tidex.conf"))
    after
      File.rm_rf!(dir)
    end
  end

  test "g writes tidex.conf at the git root, not cwd" do
    dir = tmp_dir()
    nested = Path.join(dir, "nested")
    File.mkdir_p!(nested)

    try do
      git!(dir, ["init", "-b", "main"])
      {app, _out} = app(cwd: nested, width: 80)
      assert app.state.setup.offer_git
      {:cont, app} = App.step(app, {:key, "g"})
      assert app.state.overlay == nil
      assert File.exists?(Path.join(dir, "tidex.conf"))
      refute File.exists?(Path.join(nested, "tidex.conf"))
      assert app.state.project_name == Path.basename(dir)
    after
      File.rm_rf!(dir)
    end
  end

  test "y does not write when cwd is blocked" do
    {app, out} = app(cwd: "/", width: 80)
    assert app.state.overlay == :setup
    assert app.state.setup.blocked
    refute app.state.setup.offer_cwd
    {:cont, app} = App.step(app, {:key, "y"})
    assert app.state.overlay == :setup
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "cwd is not permitted"
    refute FakeTerminal.visible(out) =~ "y  write here"
    refute File.exists?("/tidex.conf")
  end

  test "command keys are ignored while setup is open" do
    dir = tmp_dir()

    try do
      {app, _out} = app(cwd: dir)
      runner = fn _cmd, _notify, _ref -> flunk("setup should block commands") end
      app = %{app | runner: runner}
      {:cont, app} = App.handle_event(app, {:key, "t"})
      {:cont, app} = App.handle_event(app, {:key, "?"})
      assert app.state.overlay == :setup
      assert app.state.test_state == :idle
    after
      File.rm_rf!(dir)
    end
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tidex-app-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp git!(dir, args) do
    {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
  end
end
