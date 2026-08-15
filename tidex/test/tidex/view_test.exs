defmodule Tidex.ViewTest do
  use ExUnit.Case, async: true

  alias Tidex.{FakeTerminal, Layout, State, View}

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

  test "lobby draws grouped status and no output lake" do
    {output, _state} = render([])

    assert output =~ "\e[2J"
    assert output =~ "┌"
    assert output =~ "└"
    assert output =~ "status"
    refute output =~ "output"
    assert output =~ "project: exmex-talk"
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
    assert visible =~ "e  edit"
    assert visible =~ "x  stop"
    assert visible =~ "b  browse"
    assert visible =~ "g  (no repository)"
    assert visible =~ "f  tidex.conf"
    assert visible =~ "?  help"
    assert visible =~ "q  quit"
    refute visible =~ "layout"
    assert output =~ "\e[1mt"
  end

  test "shows one current test and server state under the headings" do
    {output, _} = render(test_state: :running)
    assert output =~ "running"

    {output, _} = render(test_state: :pass)
    assert output =~ "pass"

    {output, _} = render(test_state: :fail)
    assert output =~ "fail"

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

  test "always lists f tidex.conf under Files" do
    {output, _} = render(files: %{})
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Files"
    assert visible =~ "f  tidex.conf"
    refute visible =~ "1  "
  end

  test "shows (no repository) when git has no branch" do
    {output, _} = render(git: %{branch: nil, dirty: 0, untracked: 0})
    assert output =~ "(no repository)"
    refute output =~ "git:     —"
  end

  test "lobby shows the failure count and one current failure" do
    failures = [
      %{name: "test Foo", file: "test/foo_test.exs", line: 12, snippet: "left behind"}
    ]

    {output, _} = render(test_state: :fail, failures: failures)
    visible = Termex.ANSI.strip(output)
    assert visible =~ "t  1 failing"
    assert visible =~ "test Foo"
    assert visible =~ "e  test/foo_test.exs:12"
    refute visible =~ "left behind"
  end

  test "a sheet replaces the lobby commands with its own menu" do
    {output, _} = render(overlay: :server, output_lines: ["hello from server"])
    visible = Termex.ANSI.strip(output)
    assert visible =~ "start"
    assert visible =~ "esc back"
    refute visible =~ "t  idle"
    refute visible =~ "f  tidex.conf"
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
    assert visible =~ "t  1 failing"
    assert visible =~ "test Foo.bar/1"
    assert visible =~ "e  test/foo_test.exs:12"
    refute visible =~ "Assertion with == failed"
    refute output =~ "test · fail"
  end
end
