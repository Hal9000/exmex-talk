defmodule Tidex.ViewTest do
  use ExUnit.Case, async: true

  alias Tidex.{FakeTerminal, Layout, State, View, Failures}

  defp render(state_overrides) do
    {device, out} = FakeTerminal.open()

    state =
      struct(
        %State{width: 40, height: 20, project_name: "exmex-talk"},
        state_overrides
      )

    assert :ok = View.render(device, state)
    {FakeTerminal.text(out), state}
  end

  defp log_inner(state) do
    Layout.inner(Layout.sheet(state).log)
  end

  test "a modal is drawn on the lobby, smaller than the screen" do
    modal = %Tidex.Modal{
      title: "demo",
      lines: ["modal-body-unique"],
      commands: "esc back",
      max_width: 28,
      max_height: 6
    }

    {output, state} = render(modal: modal, width: 40, height: 20)
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Tidex · exmex-talk"
    assert visible =~ "t  idle"
    assert visible =~ "modal-body-unique"
    assert visible =~ "esc back"
    assert visible =~ "demo"

    pane = Tidex.Modal.pane(state, modal)
    assert pane.width < state.width
    assert pane.height < state.height
    inner = Layout.inner(pane)
    rows = FakeTerminal.region_lines(output, inner)
    assert hd(rows) =~ "modal-body-unique"
    assert List.last(rows) =~ "esc back"
    refute Enum.any?(rows, &String.contains?(&1, "project:"))
  end

  test "lobby draws grouped status and no output lake" do
    {output, _state} = render([])

    assert output =~ "\e[?25l"
    assert output =~ "\e[2J"
    assert output =~ "┌"
    assert output =~ "└"
    assert output =~ "Tidex · exmex-talk"
    refute output =~ "output"
    refute output =~ "project:"
    assert output =~ "Test"
    assert output =~ "Server"
    assert output =~ "idle"
    assert output =~ "down"
    assert output =~ "Git"
    visible = Termex.ANSI.strip(output)
    refute visible =~ "test start"
    refute visible =~ "xstop"
    refute visible =~ "?help"
    assert visible =~ "t  idle"
    assert visible =~ "s  down"
    assert visible =~ "f  fail"
    assert visible =~ "x  stop"
    assert visible =~ "b  browse"
    assert visible =~ "g  (no repository)"
    assert visible =~ "0  tidex.conf"
    assert visible =~ "?  help"
    assert visible =~ "q  quit"
    refute visible =~ "layout"
    assert output =~ "\e[1mt"
  end

  test "lobby is content-height, capped at 80 columns, and centered" do
    files = %{1 => "README.md", 2 => "lib/proj1.ex", 3 => "test/proj1_test.exs"}
    git = %{branch: "main", dirty: 3, untracked: 2}
    {output, _state} = render(width: 140, height: 40, files: files, git: git)

    pane = Layout.lobby(140, 40, 12)
    assert pane == %Layout.Pane{row: 14, col: 31, width: 80, height: 14}
    assert output =~ "\e[14;31H┌"
    assert output =~ "\e[27;31H└"
    assert output =~ "Tidex · exmex-talk"
    assert output =~ "Test"
  end

  test "shows one current test and server state under the headings" do
    {output, _} = render(test_state: :running)
    assert Termex.ANSI.strip(output) =~ "t  - pass  0 fail"

    {output, _} = render(test_state: :pass)
    assert Termex.ANSI.strip(output) =~ "t  - pass  0 fail"

    {output, _} = render(test_state: :fail)
    assert Termex.ANSI.strip(output) =~ "t  fail"

    {output, _} = render(server_state: :up)
    assert output =~ "up"
  end

  test "shows git branch, dirty, and untracked on their own lines; omits zeros" do
    {output, _} = render(git: %{branch: "main", dirty: 3, untracked: 2})
    assert output =~ "main"
    assert output =~ "3 dirty"
    assert output =~ "2 untracked"

    {output, _} = render(git: %{branch: "main", dirty: 0, untracked: 2})
    assert output =~ "2 untracked"
    refute output =~ "dirty"

    {output, _} = render(git: %{branch: "main", dirty: 0, untracked: 0})
    assert output =~ "main"
    refute output =~ "dirty"
    refute output =~ "untracked"
  end

  test "lists file1-file4 on the lobby and omits missing slots" do
    {output, _} = render(files: %{1 => "README.md", 3 => "lib/tidex.ex"})
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Files"
    assert visible =~ "1  README.md"
    assert visible =~ "3  lib/tidex.ex"
    refute visible =~ "2  "
    refute visible =~ "file1"
  end

  test "always lists 0 tidex.conf under Files" do
    {output, _} = render(files: %{})
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Files"
    assert visible =~ "0  tidex.conf"
    refute visible =~ "1  "
  end

  test "shows (no repository) when git has no branch" do
    {output, _} = render(git: %{branch: nil, dirty: 0, untracked: 0})
    assert output =~ "(no repository)"
    refute output =~ "git:     —"
  end

  test "lobby shows dash passes and a fail count, not the failure body" do
    failures = [
      %{name: "test Foo", file: "test/foo_test.exs", line: 12, snippet: "left behind"}
    ]

    {output, _} = render(test_state: :fail, failures: failures)
    visible = Termex.ANSI.strip(output)
    assert visible =~ "t  - pass  1 fail"
    assert visible =~ "f  fail"
    refute visible =~ "test Foo"
    refute visible =~ "foo_test.exs"
    refute visible =~ "left behind"
  end

  test "a sheet replaces the lobby commands with its own menu" do
    {output, _} = render(overlay: :server, output_lines: ["hello from server"])
    visible = Termex.ANSI.strip(output)
    assert visible =~ "start"
    assert visible =~ "esc back"
    refute visible =~ "t  idle"
    refute visible =~ "0  tidex.conf"
    refute visible =~ "?  help"
    refute visible =~ "test start"
  end

  test "clips output that would overflow the pane" do
    long = "KEEP_START" <> String.duplicate("x", 80) <> "KEEP_END"

    {output, _} =
      render(width: 24, height: 16, overlay: :server, output_lines: [long])

    assert output =~ "KEEP_START"
    refute output =~ "KEEP_END"
  end

  test "server sheet keeps the latest lines when they overflow height" do
    lines = Enum.map(1..20, &"row#{&1}-end")
    {output, state} = render(width: 40, height: 12, overlay: :server, output_lines: lines)
    inner = log_inner(state)
    visible = FakeTerminal.region_lines(output, inner)

    assert List.last(visible) == "row20-end"
    assert length(visible) == inner.height
    refute "row1-end" in visible
  end

  test "a pinned scroll offset shows older output instead of the tail" do
    lines = Enum.map(1..20, &"row#{&1}-end")

    {output, state} =
      render(width: 40, height: 12, overlay: :server, output_lines: lines, output_scroll: 0)

    inner = log_inner(state)
    visible = FakeTerminal.region_lines(output, inner)

    assert hd(visible) == "row1-end"
    refute "row20-end" in visible
    assert output =~ "server · down 1-"
  end

  test "last frame drops lines that scrolled out after a redraw" do
    {device, out} = FakeTerminal.open()
    lines = Enum.map(1..20, &"row#{&1}-end")

    state = %State{
      width: 40,
      height: 12,
      project_name: "exmex-talk",
      overlay: :server,
      output_lines: lines
    }

    inner = log_inner(state)

    assert :ok = View.render(device, state)
    assert List.last(FakeTerminal.region_lines(out, inner)) == "row20-end"
    assert FakeTerminal.text(out) =~ "row20-end"

    assert :ok = View.render(device, %{state | output_scroll: 0})
    visible = FakeTerminal.region_lines(out, inner)
    assert hd(visible) == "row1-end"
    refute "row20-end" in visible
    assert FakeTerminal.text(out) =~ "row20-end"
  end

  test "help sheet draws a keymap on top of the lobby" do
    {output, _} = render(overlay: :help)
    assert output =~ "help"
    assert Termex.ANSI.strip(output) =~ "t  run tests"
    assert output =~ "arrows  scroll server"
    assert output =~ "esc closes"
  end

  test "git sheet draws status text and the git keymap" do
    git = %{
      branch: "main",
      dirty: 1,
      status: "On branch main\nChanges not staged for commit:\n  modified: lib/tidex.ex"
    }

    {output, _} = render(overlay: :git, git: git)
    assert output =~ "git"
    assert Termex.ANSI.strip(output) =~ "add -u"
    assert output =~ "On branch main"
    assert output =~ "modified: lib/tidex.ex"
    assert Termex.ANSI.strip(output) =~ "esc back"
  end

  test "setup overlay asks where to write tidex.conf" do
    setup = %Tidex.Setup{
      cwd: "/tmp/demo-project",
      git_root: nil,
      offer_cwd: true,
      offer_git: false
    }

    {output, _} = render(overlay: :setup, setup: setup, width: 80)
    assert output =~ "tidex.conf"
    assert output =~ "no tidex.conf"
    assert output =~ "write in cwd"
    assert Termex.ANSI.strip(output) =~ "y  write here"
  end

  test "setup overlay states that a blocked cwd is not permitted" do
    setup = %Tidex.Setup{cwd: "/tmp", blocked: true, offer_cwd: false}
    {output, _} = render(overlay: :setup, setup: setup, width: 80)
    assert output =~ "cwd is not permitted"
    assert output =~ "/tmp"
    refute Termex.ANSI.strip(output) =~ "y  write here"
  end

  test "a failed run does not draw the test log on the lobby" do
    failures = [
      %{
        name: "test Foo.bar/1 (FooTest)",
        file: "test/foo_test.exs",
        line: 12,
        snippet: "Assertion with == failed"
      }
    ]

    {output, _} =
      render(
        test_state: :fail,
        failures: failures,
        output_lines: ["1) test Foo.bar/1 (FooTest)", "Assertion with == failed"],
        width: 40,
        height: 20
      )

    visible = Termex.ANSI.strip(output)
    assert visible =~ "t  - pass  1 fail"
    assert visible =~ "f  fail"
    refute visible =~ "test Foo.bar/1"
    refute visible =~ "Assertion with == failed"
    refute output =~ "test · fail"
  end

  test "the failure box sits on the lobby at 60x7" do
    failures = [
      %{
        name: "test Foo.bar/1 (FooTest)",
        file: "test/foo_test.exs",
        line: 12,
        snippet: "Assertion with == failed · code:  assert 1"
      }
    ]

    state_opts = [
      test_state: :fail,
      failures: failures,
      failure_index: 0,
      width: 80,
      height: 24
    ]

    modal = Failures.modal(%{failures: failures, failure_index: 0})
    {output, state} = render(Keyword.put(state_opts, :modal, modal))
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Tidex · exmex-talk"
    assert visible =~ "t  - pass  1 fail"
    assert visible =~ "test Foo.bar/1 (FooTest)"
    assert visible =~ "test/foo_test.exs:12"
    assert visible =~ "Assertion with == failed"
    assert visible =~ "fail 1/1"

    pane = Tidex.Modal.pane(state, modal)
    assert pane.width == 60
    assert pane.height == 7
    inner = Layout.inner(pane)
    rows = FakeTerminal.region_lines(output, inner)
    assert hd(rows) =~ "test Foo.bar/1"
    assert Enum.at(rows, 1) =~ "foo_test.exs:12"
    assert List.last(rows) =~ "edit"
  end
end
