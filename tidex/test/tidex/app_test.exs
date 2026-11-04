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
    Layout.inner(Layout.sheet(state).log)
  end

  defp run_tests(app) do
    {:cont, app} = App.handle_event(app, {:key, "t"})
    app
  end

  test "q quits without running a command" do
    {device, out} = FakeTerminal.open("q")
    runner = fn _cmd, _notify, _ref -> flunk("command should not run on quit") end

    assert :ok = App.start(device: device, runner: runner, width: 40, height: 20)
    output = FakeTerminal.text(out)

    assert output =~ "Tidex · exmex-talk"
    assert output =~ "\e[?25h"
    assert output =~ "tidex stopped"
  end

  test "unknown keys are ignored" do
    {device, _out} = FakeTerminal.open("z q")
    runner = fn _cmd, _notify, _ref -> flunk("unknown keys should not run a command") end

    assert :ok = App.start(device: device, runner: runner, width: 40, height: 20)
  end

  test "cwd of the example app loads that project, not Tidex" do
    root = Path.expand("../../../examples/proj1", __DIR__)
    {app, _out} = app(cwd: root)
    assert app.state.project_name == "proj1"
    assert app.state.test_command == "mix test"
    assert app.state.config_root == root
    assert app.state.files[2] == "lib/proj1.ex"
    assert app.state.overlay == nil
  end

  test "? toggles the help overlay" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "?"})
    assert app.state.overlay == :help
    assert FakeTerminal.last_frame(out) =~ "esc closes"

    {:cont, app} = App.step(app, {:key, "?"})
    assert app.state.overlay == nil
    refute FakeTerminal.last_frame(out) =~ "esc closes"
    assert FakeTerminal.text(out) =~ "esc closes"
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
    {:cont, app} = App.handle_event(app, {:key, "f"})
    {:cont, app} = App.handle_event(app, {:key, "1"})
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
    assert app.state.overlay == :git
    assert app.state.output_source == :git
    assert app.state.git_cmd_ref == ref

    {:cont, _app} = App.step(app, {:command, ref, :line, "staged"})
    assert FakeTerminal.last_frame(out) =~ "staged"
  end

  test "p from the git overlay runs git push" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "g"})
    {:cont, app} = App.handle_event(app, {:key, "p"})
    assert_receive {:started, "git push", _, _, _}
    assert app.state.overlay == :git
  end

  test "c from the git overlay yields git commit" do
    parent = self()
    editor = fn command -> send(parent, {:edited, command}) end
    {app, _out} = app(editor_runner: editor, git_reader: fn -> %{branch: "main", dirty: 0} end)

    {:cont, app} = App.step(app, {:key, "g"})
    {:cont, app} = App.step(app, {:key, "c"})
    assert_receive {:edited, "git commit"}
    assert app.state.overlay == :git
    assert app.state.git.status == ""
  end

  test "a does nothing unless the git overlay is open" do
    {app, _out} = app([])
    runner = fn _cmd, _notify, _ref -> flunk("add should not run") end
    app = %{app | runner: runner}
    {:cont, app} = App.handle_event(app, {:key, "a"})
    assert app.state.git_cmd_ref == nil
  end

  test "git add keeps the test log and stays on the git sheet" do
    {app, _out} = app([])

    app = %{
      app
      | state: %{app.state | test_log: ["test line one", "test line two"]}
    }

    {:cont, app} = App.handle_event(app, {:key, "g"})
    {:cont, app} = App.handle_event(app, {:key, "a"})
    git_ref = app.state.git_cmd_ref
    {:cont, app} = App.handle_event(app, {:command, git_ref, :line, "git add ok"})

    assert app.state.test_log == ["test line one", "test line two"]
    assert app.state.overlay == :git
    assert app.state.output_source == :git
    assert app.state.output_lines == ["git add ok"]
    assert app.state.git_log == ["git add ok"]
  end

  test "opening the server sheet keeps the test log" do
    {app, _out} = app([])

    app = %{
      app
      | state: %{app.state | test_log: ["still in the test log"]}
    }

    {:cont, app} = App.handle_event(app, {:key, "s"})
    assert app.state.test_log == ["still in the test log"]
    assert app.state.overlay == :server
    assert app.state.output_source == :server
    assert app.state.output_lines == []
  end

  test "a running test still appends while the server sheet is showing" do
    {app, _out} = app([])
    app = run_tests(app)
    test_ref = app.state.test_ref
    {:cont, app} = App.handle_event(app, {:key, "s"})
    {:cont, app} = App.handle_event(app, {:command, test_ref, :line, "still testing"})

    assert app.state.test_log == ["still testing"]
    assert app.state.overlay == :server
    assert app.state.output_source == :server
    refute "still testing" in app.state.output_lines
  end

  test "running tests again clears the last run" do
    {app, _out} = app([])

    app = %{
      app
      | state: %{
          app.state
          | test_log: ["old"],
            failures: [%{name: "old", file: "test/a.exs", line: 1, snippet: ""}]
        }
    }

    {:cont, app} = App.step(app, {:key, "t"})
    assert app.state.test_state == :running
    assert app.state.test_log == []
    assert app.state.failures == []
  end

  test "left and right do not scroll" do
    {app, _out} = app([])
    app = %{app | state: %{app.state | output_lines: Enum.map(1..25, &"row#{&1}")}}

    {:cont, app} = App.handle_event(app, {:key, :left})
    {:cont, app} = App.handle_event(app, {:key, :right})
    assert app.state.output_scroll == :follow
  end

  test "arrows do nothing on the lobby" do
    {app, _out} = app([])
    app = %{app | state: %{app.state | output_lines: Enum.map(1..25, &"row#{&1}")}}

    {:cont, app} = App.handle_event(app, {:key, :up})
    assert app.state.output_scroll == :follow
    assert app.state.overlay == nil
  end

  @exunit_fail [
    "  1) test Foo.bar/1 (FooTest)",
    "     test/foo_test.exs:12",
    "     Assertion with == failed",
    "  2) test boom (FooTest)",
    "     test/foo_test.exs:20",
    "     ** (RuntimeError) timed out"
  ]

  test "a failing test run shows the fail count on the lobby" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref
    app = %{app | state: %{app.state | test_log: @exunit_fail}}

    {:cont, app} = App.step(app, {:command, ref, :exit, 1})
    assert app.state.test_state == :fail
    assert length(app.state.failures) == 2
    assert app.state.overlay == nil
    visible = FakeTerminal.visible(out)
    assert visible =~ "t  fail     2 fail"
    assert visible =~ "f  fail"
    refute visible =~ "test Foo.bar/1"
    refute visible =~ "Assertion with == failed"
    refute visible =~ "test · fail"

    {:cont, app} = App.step(app, {:key, :right})
    assert app.state.failure_index == 0
    assert app.state.modal == nil
  end

  test "failure headers update the lobby count while tests are running" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref

    {:cont, app} = App.step(app, {:command, ref, :line, "  1) test Foo.bar/1 (FooTest)"})
    assert length(app.state.failures) == 1
    assert app.state.test_state == :running
    assert FakeTerminal.visible(out) =~ "running  1 fail"

    {:cont, app} = App.step(app, {:command, ref, :line, "     test/foo_test.exs:12"})
    {:cont, app} = App.step(app, {:command, ref, :line, "  2) test boom (FooTest)"})
    assert length(app.state.failures) == 2
    assert FakeTerminal.visible(out) =~ "running  2 fail"
    refute FakeTerminal.visible(out) =~ "test boom"
  end

  test "a passing run clears parsed failures" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref
    app = %{app | state: %{app.state | test_log: @exunit_fail, failures: [%{name: "old"}]}}

    {:cont, app} = App.step(app, {:command, ref, :exit, 0})
    assert app.state.test_state == :pass
    assert app.state.failures == []
    visible = FakeTerminal.visible(out)
    assert visible =~ "t  pass"
    refute visible =~ "2 fail"
  end

  test "handle_event q returns quit" do
    {app, _out} = app([])
    assert {:quit, ^app} = App.handle_event(app, {:key, "q"})
  end

  test "t from the lobby starts the test command" do
    {app, out} = app(test_command: "mix test")
    assert {:cont, app} = App.step(app, {:key, "t"})

    assert_receive {:started, "mix test", notify, ref, _pid}
    assert notify == self()
    assert app.state.overlay == nil
    assert app.state.test_state == :running
    assert app.state.test_ref == ref
    visible = FakeTerminal.visible(out)
    assert visible =~ "running  0 fail"
    refute visible =~ "test · running"
  end

  test "test output is kept but not drawn on the lobby" do
    {app, out} = app(test_command: "mix test")
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref

    {:cont, app} = App.step(app, {:command, ref, :line, "one"})
    assert app.state.test_log == ["one"]
    refute FakeTerminal.visible(out) =~ "one"
    assert app.state.test_state == :running

    {:cont, app} = App.step(app, {:command, ref, :line, "two"})
    assert app.state.test_log == ["one", "two"]
    refute FakeTerminal.visible(out) =~ "two"

    {:cont, app} = App.step(app, {:command, ref, :exit, 0})
    assert app.state.test_state == :pass
    visible = FakeTerminal.visible(out)
    assert visible =~ "t  pass"
    refute visible =~ "one"
    refute visible =~ "test · pass"
  end

  test "non-zero test exit marks tests as fail" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref
    {:cont, app} = App.step(app, {:command, ref, :exit, 1})

    assert app.state.test_state == :fail
    visible = FakeTerminal.visible(out)
    assert visible =~ "t  fail"
    refute visible =~ "t  running"
    refute visible =~ "test · fail"
  end

  test "s from the lobby opens the server sheet without starting" do
    {app, out} = app(server_command: "python3 -m http.server 4000")
    {:cont, app} = App.step(app, {:key, "s"})

    refute_received {:started, _, _, _, _}
    assert app.state.overlay == :server
    assert app.state.server_state == :down
    assert FakeTerminal.last_frame(out) =~ "server · down"
  end

  test "s on the server sheet starts the server and streams into it" do
    {app, out} = app(server_command: "python3 -m http.server 4000")
    {:cont, app} = App.step(app, {:key, "s"})
    {:cont, app} = App.step(app, {:key, "s"})

    assert_receive {:started, "python3 -m http.server 4000", _notify, ref, _pid}
    assert app.state.server_state == :up
    assert FakeTerminal.last_frame(out) =~ "server · up"

    {:cont, _app} = App.step(app, {:command, ref, :line, "listening"})
    assert FakeTerminal.region_lines(out, output_inner(app.state)) == ["listening"]
  end

  test "s restarts a running server" do
    parent = self()
    {app, _out} = app(runner: fake_runner(parent), server_command: "server")

    {:cont, app} = App.step(app, {:key, "s"})
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
    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, _, pid}
    assert Process.alive?(pid)

    {:cont, app} = App.step(app, {:key, "x"})
    refute Process.alive?(pid)
    assert app.state.server_state == :down
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "server · down"
    refute frame =~ "server · up"
  end

  test "b launches the browser url" do
    {app, _out} = app(browser_url: "http://localhost:4000")
    {:cont, _app} = App.step(app, {:key, "b"})
    assert_receive {:browser, "http://localhost:4000"}
  end

  test "e does nothing on the lobby" do
    parent = self()
    editor = fn command -> send(parent, {:edited, command}) end
    {app, _out} = app(editor_command: "true", editor_runner: editor)

    {:cont, app} = App.step(app, {:key, "e"})
    refute_received {:edited, _}
    assert app.state.modal == nil
  end

  test "0 yields the editor on tidex.conf" do
    parent = self()
    editor = fn command -> send(parent, {:edited, command}) end

    {app, _out} =
      app(
        editor_command: "nvim",
        editor_runner: editor,
        config_path: "/tmp/demo/tidex.conf"
      )

    {:cont, _app} = App.step(app, {:key, "0"})
    assert_receive {:edited, "nvim '/tmp/demo/tidex.conf'"}
  end

  test "1 opens file1 from the listed files" do
    parent = self()
    editor = fn command -> send(parent, {:edited, command}) end

    {app, _out} =
      app(
        editor_command: "nvim",
        editor_runner: editor,
        files: %{1 => "README.md", 3 => "lib/tidex.ex"},
        config_root: "/proj"
      )

    {:cont, _app} = App.step(app, {:key, "1"})
    assert_receive {:edited, "nvim '/proj/README.md'"}
  end

  test "2 does nothing when file2 is not listed" do
    {app, _out} = app(files: %{1 => "README.md"})
    runner = fn _cmd -> flunk("missing file2 should not open an editor") end
    app = %{app | editor_runner: runner}
    {:cont, app} = App.handle_event(app, {:key, "2"})
    assert app.state.overlay == nil
  end

  test "1 does nothing unless a listed file is present" do
    {app, _out} = app(files: %{})
    runner = fn _cmd -> flunk("no listed files should not open an editor") end
    app = %{app | editor_runner: runner}
    {:cont, app} = App.handle_event(app, {:key, "1"})
    assert app.state.overlay == nil
  end

  test "e in the failure box opens the current failure at line" do
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

    {:cont, app} = App.step(app, {:key, "f"})
    assert app.state.modal.kind == :fail
    assert app.state.modal.title == "fail 2/2"

    {:cont, _app} = App.step(app, {:key, "e"})
    assert_receive {:edited, "nvim +9 'test/b.exs'"}
  end

  test "f opens the failure box; esc and f close it" do
    {app, out} = app(width: 80, height: 24)

    app = %{
      app
      | state: %{
          app.state
          | failures: [
              %{name: "test Foo", file: "test/a.exs", line: 3, snippet: "left behind"}
            ]
        }
    }

    {:cont, app} = App.step(app, {:key, "f"})
    assert app.state.modal.kind == :fail
    visible = FakeTerminal.visible(out)
    assert visible =~ "test Foo"
    assert visible =~ "test/a.exs:3"
    assert visible =~ "left behind"
    assert visible =~ "fail 1/1"
    assert visible =~ "Tidex · exmex-talk"

    {:cont, app} = App.step(app, {:key, :esc})
    assert app.state.modal == nil
    refute FakeTerminal.visible(out) =~ "test Foo"

    {:cont, app} = App.step(app, {:key, "f"})
    assert app.state.modal.kind == :fail
    {:cont, app} = App.step(app, {:key, "f"})
    assert app.state.modal == nil
  end

  test "f does nothing when there are no failures" do
    {app, _out} = app([])
    {:cont, app} = App.step(app, {:key, "f"})
    assert app.state.modal == nil
  end

  test "left and right cycle only inside the failure box" do
    {app, out} = app(width: 80, height: 24)

    app = %{
      app
      | state: %{
          app.state
          | failures: [
              %{name: "one", file: "test/a.exs", line: 1, snippet: "first"},
              %{name: "two", file: "test/b.exs", line: 2, snippet: "second"}
            ]
        }
    }

    {:cont, app} = App.step(app, {:key, :right})
    assert app.state.failure_index == 0
    assert app.state.modal == nil

    {:cont, app} = App.step(app, {:key, "f"})
    assert FakeTerminal.visible(out) =~ "one"
    refute FakeTerminal.visible(out) =~ "two"

    {:cont, app} = App.step(app, {:key, :right})
    assert app.state.failure_index == 1
    assert FakeTerminal.visible(out) =~ "two"
    refute FakeTerminal.visible(out) =~ "one"

    {:cont, app} = App.step(app, {:key, :left})
    assert app.state.failure_index == 0
    assert FakeTerminal.visible(out) =~ "one"
  end

  test "the failure box swallows lobby keys" do
    {app, _out} = app([])

    app = %{
      app
      | state: %{
          app.state
          | failures: [%{name: "one", file: "a.exs", line: 1, snippet: "x"}]
        }
    }

    {:cont, app} = App.step(app, {:key, "f"})
    {:cont, app} = App.step(app, {:key, "t"})
    assert app.state.test_state == :idle
    assert app.state.modal.kind == :fail
  end

  test "a parsed failing run can open the failure box" do
    {app, out} = app(width: 80, height: 24)
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref
    app = %{app | state: %{app.state | test_log: @exunit_fail}}
    {:cont, app} = App.step(app, {:command, ref, :exit, 1})
    {:cont, app} = App.step(app, {:key, "f"})
    assert app.state.modal.kind == :fail
    visible = FakeTerminal.visible(out)
    assert visible =~ "test Foo.bar/1 (FooTest)"
    assert visible =~ "test/foo_test.exs:12"
    refute visible =~ "  1) "
  end

  test "l does nothing on the lobby" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "l"})
    assert app.state.overlay == nil
    assert app.state.test_state == :idle
  end

  test "git snapshots update the status pane" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:git, %{branch: "main", dirty: 4, untracked: 1}})
    assert app.state.git == %{branch: "main", dirty: 4, untracked: 1, status: ""}
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "main"
    assert frame =~ "4 dirty"
    assert frame =~ "1 untracked"
  end

  test "stale command lines from a previous run are ignored" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "t"})
    old_ref = app.state.test_ref
    {:cont, app} = App.step(app, {:key, "t"})
    new_ref = app.state.test_ref

    {:cont, app} = App.step(app, {:command, old_ref, :line, "stale"})
    refute "stale" in app.state.test_log
    refute FakeTerminal.visible(out) =~ "stale"

    {:cont, app} = App.step(app, {:command, new_ref, :line, "fresh"})
    assert app.state.test_log == ["fresh"]
    refute FakeTerminal.visible(out) =~ "fresh"
  end

  test "server process exit marks the server down" do
    {app, out} = app(server_command: "server")
    {:cont, app} = App.step(app, {:key, "s"})
    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, ref, _pid}

    {:cont, app} = App.step(app, {:command, ref, :exit, 1})
    assert app.state.server_state == :down
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "server · down"
    refute frame =~ "server · up"
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
    {:cont, app} = App.step(app, {:key, "0"})

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

    {app, _out} = app(config: config, files: %{1 => "README.md"})
    assert app.state.project_name == "demo"
    assert app.state.test_command == "echo tests"
    assert app.state.server_command == "echo serve"
    assert app.state.browser_url == "http://example.test"
    assert app.state.editor_command == "true"
    assert app.state.files == %{1 => "README.md"}
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
      File.write!(Path.join(dir, "README.md"), "hi\n")
      home = Path.join(dir, "user")
      {app, _out} = app(cwd: dir, home: home)
      {:cont, app} = App.step(app, {:key, "y"})
      assert app.state.overlay == nil
      assert File.exists?(Path.join(dir, "tidex.conf"))
      assert app.state.project_name == Path.basename(dir)
      assert app.state.files == %{1 => "README.md"}
      body = File.read!(Path.join(dir, "tidex.conf"))
      refute body =~ ~r/^editor:/m
      assert body =~ ~r/^file1: README.md$/m
      user = Tidex.Home.load(home: home)
      assert Tidex.Home.lookup(user, dir) == Path.basename(dir)
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
      home = Path.join(dir, "user")
      {app, _out} = app(cwd: nested, width: 80, home: home)
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
