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

    project_defaults =
      if Keyword.has_key?(opts, :cwd) or Keyword.has_key?(opts, :config) do
        []
      else
        [
          server_command: "server",
          browser_url: "http://localhost:4000",
          git: %{root: "/repo", branch: "main", dirty: 0, untracked: 0, status: ""}
        ]
      end

    app =
      App.new(
        Keyword.merge(
          [
            device: device,
            runner: fake_runner(),
            editor_runner: fn _ -> :ok end,
            browser_runner: fn url -> send(self(), {:browser, url}) end,
            server_probe: fn _url -> :unsupported end,
            server_waiter: fn _url -> :unsupported end,
            probe_scheduler: fn _message, _delay -> :ok end,
            width: 80,
            height: 24,
            keys: :none
          ] ++ project_defaults,
          opts
        )
      )

    {app, out}
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

  test "shutdown reports a server cleanup failure" do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    {app, out} = app(server_stopper: fn ^pid -> {:error, :still_running} end)
    app = %{app | state: %{app.state | server_pid: pid}}

    assert :ok = App.shutdown(app)
    assert FakeTerminal.text(out) =~ "tidex stopped; server cleanup failed"
    Process.exit(pid, :kill)
  end

  test "unknown keys are ignored" do
    {device, _out} = FakeTerminal.open("z q")
    runner = fn _cmd, _notify, _ref -> flunk("unknown keys should not run a command") end

    assert :ok = App.start(device: device, runner: runner, width: 40, height: 20)
  end

  test "refreshes terminal dimensions before the next redraw" do
    dimensions = start_supervised!({Agent, fn -> {80, 24} end})
    {device, _out} = FakeTerminal.open()

    app =
      App.new(
        device: device,
        config: %Tidex.Config{},
        dimension_reader: fn -> Agent.get(dimensions, & &1) end,
        resize: true,
        keys: :none
      )

    assert app.state.width == 80
    assert app.state.height == 24

    Agent.update(dimensions, fn _ -> {120, 40} end)
    {:cont, app} = App.step(app, {:key, "z"})

    assert app.state.width == 120
    assert app.state.height == 40
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

  test "? toggles the help modal over the lobby" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "?"})
    assert app.state.overlay == nil
    assert app.state.modal.kind == :help
    assert FakeTerminal.last_frame(out) =~ "esc close"
    assert FakeTerminal.last_frame(out) =~ "Tidex · exmex-talk"

    {:cont, app} = App.step(app, {:key, "?"})
    assert app.state.modal == nil
    assert app.state.overlay == nil
    refute FakeTerminal.last_frame(out) =~ "esc close"
    assert FakeTerminal.text(out) =~ "esc close"
  end

  test "esc closes the help modal" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "?"})
    {:cont, app} = App.handle_event(app, {:key, :esc})
    assert app.state.modal == nil
    assert app.state.overlay == nil
  end

  test "help menu selects topics, opens details, scrolls, and backs out" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "?"})
    assert app.state.modal.page == :menu
    assert app.state.modal.selection == 0

    {:cont, app} = App.handle_event(app, {:key, "\t"})
    {:cont, app} = App.handle_event(app, {:key, :down})
    {:cont, app} = App.handle_event(app, {:key, :up})
    assert app.state.modal.selection == 1

    {:cont, app} = App.handle_event(app, {:key, "\r"})
    assert app.state.modal.page == {:topic, :failures}
    assert app.state.modal.title == "help · Failures"

    {:cont, app} = App.handle_event(app, {:key, :down})
    assert app.state.modal.scroll == 1

    {:cont, app} = App.handle_event(app, {:key, :esc})
    assert app.state.modal.page == :menu
    assert app.state.modal.selection == 1

    {:cont, app} = App.handle_event(app, {:key, :esc})
    assert app.state.modal == nil
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
    assert app.state.modal.kind == :help
    assert app.state.test_state == :idle
  end

  test "q still quits while help is open" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "?"})
    assert {:quit, ^app} = App.handle_event(app, {:key, "q"})
  end

  test "g toggles the git modal over the lobby" do
    git = %{branch: "main", dirty: 1, status: "On branch main\nmodified: lib/tidex.ex"}
    {app, out} = app(git: git)
    {:cont, app} = App.step(app, {:key, "g"})
    assert app.state.overlay == nil
    assert app.state.modal.kind == :git
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "Tidex · exmex-talk"
    assert frame =~ "On branch main"
    assert FakeTerminal.visible(out) =~ "Add tracked changes"
    assert FakeTerminal.visible(out) =~ "Ship (add, commit, rebase, push)"

    {:cont, app} = App.step(app, {:key, "g"})
    assert app.state.modal == nil
    refute FakeTerminal.visible(out) =~ "Add tracked changes"
    assert Termex.ANSI.strip(FakeTerminal.text(out)) =~ "Add tracked changes"
  end

  test "git off suppresses polling, updates, and Git modal keys" do
    {app, out} =
      app(
        git_mode: :off,
        poll_git: true,
        git_reader: fn -> flunk("disabled Git should not be read") end
      )

    app = App.attach_git(app)
    assert app.git_pid == nil

    {:cont, app} = App.step(app, {:key, "g"})
    assert app.state.modal == nil
    assert FakeTerminal.visible(out) =~ "[Git disabled]"

    {:cont, app} = App.handle_event(app, {:key, "i"})
    assert app.state.modal == nil

    {:cont, app} =
      App.handle_event(app, {:git, %{branch: "unexpected", dirty: 1, untracked: 0}})

    assert app.state.git.branch == "main"
  end

  test "Git modal keys do nothing when auto-detection finds no repository" do
    no_repo = %{root: nil, branch: nil, dirty: 0, untracked: 0, status: ""}
    {app, out} = app(git: no_repo)

    {:cont, app} = App.step(app, {:key, "g"})
    assert app.state.modal == nil
    assert FakeTerminal.visible(out) =~ "[No Git repository]"

    {:cont, app} = App.handle_event(app, {:key, "i"})
    assert app.state.modal == nil
  end

  test "esc closes the git modal" do
    {app, _out} = app([])
    {:cont, app} = App.step(app, {:key, "g"})
    {:cont, app} = App.handle_event(app, {:key, :esc})
    assert app.state.modal == nil
  end

  test "a from the git modal runs git add -u" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "g"})
    {:cont, app} = App.step(app, {:key, "a"})

    assert_receive {:started, "git add -u", _notify, ref, _pid}
    assert app.state.modal.kind == :git
    assert app.state.output_source == :git
    assert app.state.git_cmd_ref == ref

    {:cont, _app} = App.step(app, {:command, ref, :line, "staged"})
    assert FakeTerminal.last_frame(out) =~ "staged"
  end

  test "p from the git modal runs git push" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "g"})
    {:cont, app} = App.handle_event(app, {:key, "p"})
    assert_receive {:started, "git push", _, _, _}
    assert app.state.modal.kind == :git
  end

  test "l from the git modal runs a fast-forward-only pull" do
    {app, _out} = app([])
    {:cont, app} = App.handle_event(app, {:key, "g"})
    {:cont, app} = App.handle_event(app, {:key, "l"})
    assert_receive {:started, "git pull --ff-only", _, _, _}
    assert app.state.modal.kind == :git
  end

  test "c accepts a one-line message and safely starts git commit" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "g"})
    {:cont, app} = App.step(app, {:key, "c"})
    assert {:commit, "", :follow} = app.state.modal.page
    assert FakeTerminal.visible(out) =~ "Message: "
    assert FakeTerminal.visible(out) =~ "enter commit"

    app =
      "Fix q gap's pullx"
      |> String.graphemes()
      |> Enum.reduce(app, fn key, app ->
        {:cont, app} = App.handle_event(app, {:key, key})
        app
      end)

    {:cont, app} =
      App.handle_event(app, {:git, %{branch: "main", dirty: 1, untracked: 0}})

    assert {:commit, "Fix q gap's pullx", :follow} = app.state.modal.page

    {:cont, app} = App.handle_event(app, {:key, <<127>>})
    assert {:commit, "Fix q gap's pull", :follow} = app.state.modal.page

    {:cont, app} = App.handle_event(app, {:key, "\r"})
    assert_receive {:started, "git commit -m 'Fix q gap'\"'\"'s pull'", _, _, _}
    assert app.state.modal.kind == :git
    assert app.state.modal.page == :status
  end

  test "empty commit does nothing and esc cancels input" do
    runner = fn _command, _notify, _ref -> flunk("empty commit should not run") end
    {app, _out} = app(runner: runner)

    {:cont, app} = App.handle_event(app, {:key, "g"})
    {:cont, app} = App.handle_event(app, {:key, "c"})
    {:cont, app} = App.handle_event(app, {:key, "\r"})
    assert {:commit, "", :follow} = app.state.modal.page

    {:cont, app} = App.handle_event(app, {:key, :esc})
    assert app.state.modal.page == :status
  end

  test "u prompts for a message and runs the ship pipeline" do
    {app, out} = app([])
    {:cont, app} = App.step(app, {:key, "g"})
    {:cont, app} = App.step(app, {:key, "u"})
    assert {:ship, "", :follow} = app.state.modal.page
    assert FakeTerminal.visible(out) =~ "enter ship"

    app =
      "Release 1"
      |> String.graphemes()
      |> Enum.reduce(app, fn key, app ->
        {:cont, app} = App.handle_event(app, {:key, key})
        app
      end)

    {:cont, app} = App.handle_event(app, {:key, "\r"})

    assert_receive {:started,
                    "git add -u && git commit -m 'Release 1' && git pull --rebase && git push", _,
                    _, _}

    assert app.state.modal.page == :status
  end

  test "a does nothing unless the git modal is open" do
    {app, _out} = app([])
    runner = fn _cmd, _notify, _ref -> flunk("add should not run") end
    app = %{app | runner: runner}
    {:cont, app} = App.handle_event(app, {:key, "a"})
    assert app.state.git_cmd_ref == nil
  end

  test "git add keeps the test log and stays in the git modal" do
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
    assert app.state.modal.kind == :git
    assert app.state.output_source == :git
    assert app.state.output_lines == ["git add ok"]
    assert app.state.git_log == ["git add ok"]
  end

  test "the git modal scrolls and seals unrelated command keys" do
    status = 1..25 |> Enum.map_join("\n", &"status line #{&1}")
    {app, out} = app(git: %{branch: "main", dirty: 25, status: status})

    {:cont, app} = App.step(app, {:key, "g"})
    assert app.state.modal.scroll == :follow
    assert FakeTerminal.visible(out) =~ "Add tracked changes"

    {:cont, app} = App.step(app, {:key, :up})
    assert is_integer(app.state.modal.scroll)
    assert FakeTerminal.visible(out) =~ "Add tracked changes"

    {:cont, app} = App.handle_event(app, {:key, "t"})
    assert app.state.test_state == :idle
    assert app.state.modal.kind == :git
  end

  test "starting the server stays on the lobby and keeps the test log" do
    {app, _out} = app([])

    app = %{
      app
      | state: %{app.state | test_log: ["still in the test log"]}
    }

    {:cont, app} = App.handle_event(app, {:key, "s"})
    assert_receive {:started, _, _, _, pid}
    assert app.state.test_log == ["still in the test log"]
    assert app.state.overlay == nil
    assert app.state.output_source == nil
    assert app.state.output_lines == []
    Process.exit(pid, :kill)
  end

  test "test and server output append independently on the lobby" do
    {app, _out} = app([])
    app = run_tests(app)
    test_ref = app.state.test_ref
    {:cont, app} = App.handle_event(app, {:key, "s"})
    server_ref = app.state.server_ref
    {:cont, app} = App.handle_event(app, {:command, test_ref, :line, "still testing"})
    {:cont, app} = App.handle_event(app, {:command, server_ref, :line, "server line"})

    assert app.state.test_log == ["still testing"]
    assert app.state.server_log == ["server line"]
    assert app.state.overlay == nil
    assert app.state.output_source == nil
    refute "still testing" in app.state.output_lines
    Process.exit(app.state.test_pid, :kill)
    Process.exit(app.state.server_pid, :kill)
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

  @minitest_fail [
    "  1) Failure:",
    "CalculatorTest#test_add [test/calculator_test.rb:8]:",
    "Expected: 5",
    "  Actual: 4"
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
    assert visible =~ "2 fail"
    assert visible =~ "Step through failures"
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
    assert FakeTerminal.visible(out) =~ "Running"
    assert FakeTerminal.visible(out) =~ "1 fail"

    {:cont, app} = App.step(app, {:command, ref, :line, "     test/foo_test.exs:12"})
    {:cont, app} = App.step(app, {:command, ref, :line, "  2) test boom (FooTest)"})
    assert length(app.state.failures) == 2
    assert FakeTerminal.visible(out) =~ "2 fail"
    refute FakeTerminal.visible(out) =~ "test boom"
  end

  test "a configured Minitest run feeds the same failure modal" do
    {app, out} = app(test_format: :minitest, width: 80, height: 24)
    {:cont, app} = App.step(app, {:key, "t"})
    ref = app.state.test_ref

    app =
      Enum.reduce(@minitest_fail, app, fn line, app ->
        {:cont, app} = App.step(app, {:command, ref, :line, line})
        app
      end)

    {:cont, app} = App.step(app, {:command, ref, :exit, 1})
    assert app.state.test_state == :fail
    assert [%{file: "test/calculator_test.rb", line: 8}] = app.state.failures

    {:cont, app} = App.step(app, {:key, "f"})
    assert app.state.modal.kind == :fail
    visible = FakeTerminal.visible(out)
    assert visible =~ "CalculatorTest#test_add"
    assert visible =~ "test/calculator_test.rb:8"
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
    assert visible =~ "pass"
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
    assert visible =~ "Running"
    refute visible =~ "1 fail"
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
    assert visible =~ "pass"
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
    assert visible =~ "Fail"
    refute visible =~ "Running"
    refute visible =~ "test · fail"
  end

  test "s starts the server directly from the lobby and retains its output" do
    {app, out} = app(server_command: "server")
    {:cont, app} = App.step(app, {:key, "s"})

    assert_receive {:started, "server", _notify, ref, pid}
    assert app.state.overlay == nil
    assert app.state.server_state == :up
    assert FakeTerminal.visible(out) =~ "up"
    refute FakeTerminal.visible(out) =~ "s  up"

    {:cont, app} = App.step(app, {:command, ref, :line, "listening"})
    assert app.state.server_log == ["listening"]
    refute FakeTerminal.visible(out) =~ "listening"
    Process.exit(pid, :kill)
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
    visible = FakeTerminal.visible(out)
    assert visible =~ "down"
    refute visible =~ "s  down"
    refute visible =~ "s  up"
  end

  test "a failed stop remains tracked and blocks restart" do
    parent = self()

    stopper = fn pid ->
      send(parent, {:stop_attempt, pid})
      {:error, :still_running}
    end

    {app, out} =
      app(
        runner: fake_runner(parent),
        server_stopper: stopper,
        server_command: "server"
      )

    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, ref, pid}

    {:cont, app} = App.step(app, {:key, "x"})
    assert_receive {:stop_attempt, ^pid}
    assert app.state.server_state == :stop_failed
    assert app.state.server_pid == pid
    assert app.state.server_ref == ref
    assert FakeTerminal.visible(out) =~ "stop failed"

    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:stop_attempt, ^pid}
    refute_receive {:started, "server", _, _, _}
    assert app.state.server_state == :stop_failed
    Process.exit(pid, :kill)
  end

  test "a server launch error is visible instead of crashing Tidex" do
    server_runner = fn _command, _notify, _ref -> {:error, :enoent} end
    {app, out} = app(server_runner: server_runner, server_command: "server")

    {:cont, app} = App.step(app, {:key, "s"})

    assert app.state.server_state == :start_failed
    assert app.state.server_pid == nil
    assert app.state.server_ref == nil
    assert FakeTerminal.visible(out) =~ "start failed"
  end

  test "a stale server exit cannot mark a restarted server down" do
    parent = self()
    {app, _out} = app(runner: fake_runner(parent), server_command: "server")

    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, old_ref, _old_pid}
    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, new_ref, new_pid}

    {:cont, app} = App.step(app, {:command, old_ref, :exit, 143})

    assert app.state.server_state == :up
    assert app.state.server_ref == new_ref
    assert app.state.server_pid == new_pid
    Process.exit(new_pid, :kill)
  end

  test "b launches the browser url" do
    {app, _out} = app(browser_url: "http://localhost:4000")
    {:cont, _app} = App.step(app, {:key, "b"})
    assert_receive {:browser, "http://localhost:4000"}
  end

  test "server and browser keys are disabled when they are not configured" do
    runner = fn _command, _notify, _ref -> flunk("server should not start") end
    browser = fn _url -> flunk("browser should not open") end

    {app, _out} =
      app(
        server_command: nil,
        browser_url: nil,
        runner: runner,
        browser_runner: browser
      )

    {:cont, app} = App.step(app, {:key, "s"})
    {:cont, app} = App.step(app, {:key, "x"})
    {:cont, app} = App.step(app, {:key, "b"})

    assert app.state.server_state == :down
    assert app.state.server_pid == nil
  end

  test "an unmanaged listener blocks start without being killed" do
    runner = fn _command, _notify, _ref -> flunk("busy port should block start") end

    {app, out} =
      app(
        runner: runner,
        server_command: "server",
        server_probe: fn _url -> :listening end
      )

    {:cont, app} = App.step(app, {:key, "s"})

    assert app.state.server_state == :port_busy
    assert app.state.server_pid == nil
    assert FakeTerminal.visible(out) =~ "port busy"

    {:cont, app} = App.step(app, {:key, "x"})
    assert app.state.server_state == :port_busy
  end

  test "a local listener moves the tracked server from starting to up" do
    {:ok, probe} = Agent.start_link(fn -> [:closed, :closed, :listening] end)

    probe_fun = fn _url ->
      Agent.get_and_update(probe, fn [status | rest] -> {status, rest} end)
    end

    {app, _out} =
      app(
        server_command: "server",
        server_probe: probe_fun,
        probe_scheduler: fn _message, _delay -> :ok end
      )

    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, ref, pid}
    assert app.state.server_state == :starting

    {:cont, app} = App.step(app, {:server_probe, ref})
    assert app.state.server_state == :up
    Process.exit(pid, :kill)
  end

  test "a listener left after confirmed stop is reported as a stop failure" do
    {:ok, probe} = Agent.start_link(fn -> [:closed, :unsupported] end)

    probe_fun = fn _url ->
      Agent.get_and_update(probe, fn [status | rest] -> {status, rest} end)
    end

    {app, _out} =
      app(
        server_command: "server",
        server_probe: probe_fun,
        server_waiter: fn _url -> :listening end
      )

    {:cont, app} = App.step(app, {:key, "s"})
    assert_receive {:started, "server", _, _, _pid}

    {:cont, app} = App.step(app, {:key, "x"})

    assert app.state.server_state == :stop_failed
    assert app.state.server_pid == nil
    assert app.state.server_ref == nil
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
    path = Path.expand("test/b.exs", app.state.config_root)
    assert_receive {:edited, "nvim +9 '" <> ^path <> "'"}
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

  test "f shows raw output when a failed test run has no parsed failure" do
    {app, out} = app([])

    app = %{
      app
      | state: %{
          app.state
          | test_state: :fail,
            test_log: ["== Compilation error in file lib/demo.ex ==", "** (SyntaxError) bad"]
        }
    }

    {:cont, app} = App.step(app, {:key, "f"})
    assert app.state.modal.kind == :output
    assert app.state.modal.page == :test
    assert FakeTerminal.visible(out) =~ "Compilation error"
    assert FakeTerminal.visible(out) =~ "SyntaxError"
    refute FakeTerminal.visible(out) =~ "edit"

    {:cont, app} = App.step(app, {:key, "f"})
    assert app.state.modal == nil
  end

  test "raw failure output reports when the command emitted nothing" do
    {app, out} = app([])
    app = %{app | state: %{app.state | test_state: :fail, test_log: []}}

    {:cont, _app} = App.step(app, {:key, "f"})
    assert FakeTerminal.visible(out) =~ "(no output)"
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
    assert visible =~ "test Foo.bar/1"
    assert visible =~ "FooTest test/foo_test.exs:12"
    refute visible =~ "(FooTest)"
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
    assert app.state.git == %{root: nil, branch: "main", dirty: 4, untracked: 1, status: ""}
    frame = FakeTerminal.last_frame(out)
    assert frame =~ "dirty"
    refute frame =~ "untracked"
    refute frame =~ "main"
  end

  test "i opens a compact, live git info modal" do
    git = %{branch: "feature/short-summary", dirty: 4, untracked: 1, status: ""}
    {app, out} = app(git: git)
    {:cont, app} = App.step(app, {:key, "i"})
    assert app.state.modal.kind == :git_info
    visible = FakeTerminal.visible(out)
    assert visible =~ "branch: feature/short-summary"
    assert visible =~ "4 tracked changes"
    assert visible =~ "1 untracked file"

    {:cont, app} =
      App.step(app, {:git, %{branch: "main", dirty: 0, untracked: 2, status: ""}})

    visible = FakeTerminal.visible(out)
    assert visible =~ "branch: main"
    assert visible =~ "0 tracked changes"
    assert visible =~ "2 untracked files"

    {:cont, app} = App.step(app, {:key, :esc})
    assert app.state.modal == nil
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
    assert_receive {:started, "server", _, ref, _pid}

    {:cont, app} = App.step(app, {:command, ref, :exit, 1})
    assert app.state.server_state == :down
    visible = FakeTerminal.visible(out)
    assert visible =~ "down"
    refute visible =~ "s  down"
    refute visible =~ "s  up"
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

  test "setup applies the detected Ruby parser after writing config" do
    dir = tmp_dir()

    try do
      File.write!(Path.join(dir, ".ruby-version"), "3.3\n")
      home = Path.join(dir, "user")
      {app, _out} = app(cwd: dir, home: home)
      app = %{app | state: %{app.state | test_format: :exunit}}

      {:cont, app} = App.step(app, {:key, "y"})

      assert app.state.test_format == :minitest
      assert app.state.test_command =~ "ruby -Itest"
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
    refute FakeTerminal.visible(out) =~ "y write here"
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
