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

  defp output_inner(state) do
    layout = Layout.compute(state)
    Layout.inner(layout.output)
  end

  test "draws a two-pane layout with status and output boxes" do
    {output, _state} = render([])

    assert output =~ "\e[2J"
    assert output =~ "┌"
    assert output =~ "└"
    assert output =~ "status"
    assert output =~ "output"
    assert output =~ "project: exmex-talk"
    assert output =~ "tests:   idle"
    assert output =~ "server:  down"
    assert output =~ "git:"
    visible = Termex.ANSI.strip(output)
    assert visible =~ "test start xstop browse"
    assert visible =~ "edit layout git ?help quit"
    assert output =~ "\e[1mt"
  end

  test "shows test and server state in the status pane" do
    {output, _} = render(test_state: :running)
    assert output =~ "tests:   running"

    {output, _} = render(test_state: :pass)
    assert output =~ "tests:   pass"

    {output, _} = render(test_state: :fail)
    assert output =~ "tests:   fail"

    {output, _} = render(server_state: :up)
    assert output =~ "server:  up"
  end

  test "shows git branch and dirty count" do
    {output, _} = render(git: %{branch: "main", dirty: 3})
    assert output =~ "main"
    assert output =~ "3 dirty"
  end

  test "displays command output inside the output pane" do
    {output, _} = render(output_lines: ["hello from tests"])
    assert output =~ "hello from tests"
  end

  test "clips output that would overflow the pane" do
    long = "KEEP_START" <> String.duplicate("x", 80) <> "KEEP_END"
    {output, _} = render(width: 24, height: 16, output_lines: [long])

    assert output =~ "KEEP_START"
    refute output =~ "KEEP_END"
  end

  test "output pane keeps the latest lines when they overflow height" do
    lines = Enum.map(1..20, &"row#{&1}-end")
    {output, state} = render(width: 40, height: 12, output_lines: lines)
    inner = output_inner(state)
    visible = FakeTerminal.region_lines(output, inner)

    assert visible == ["row19-end", "row20-end"]
    assert length(visible) == inner.height
    refute "row1-end" in visible
  end

  test "a pinned scroll offset shows older output instead of the tail" do
    lines = Enum.map(1..20, &"row#{&1}-end")

    {output, state} =
      render(width: 40, height: 12, output_lines: lines, output_scroll: 0)

    inner = output_inner(state)
    visible = FakeTerminal.region_lines(output, inner)

    assert visible == ["row1-end", "row2-end"]
    refute "row20-end" in visible
    assert output =~ "output 1-"
  end

  test "last frame drops lines that scrolled out after a redraw" do
    {device, out} = FakeTerminal.open()
    lines = Enum.map(1..20, &"row#{&1}-end")

    state = %State{
      width: 40,
      height: 12,
      project_name: "exmex-talk",
      output_lines: lines
    }

    inner = output_inner(state)

    assert :ok = View.render(device, state)
    assert FakeTerminal.region_lines(out, inner) == ["row19-end", "row20-end"]
    assert FakeTerminal.text(out) =~ "row20-end"

    assert :ok = View.render(device, %{state | output_scroll: 0})
    visible = FakeTerminal.region_lines(out, inner)
    assert visible == ["row1-end", "row2-end"]
    refute "row20-end" in visible
    assert FakeTerminal.text(out) =~ "row20-end"
  end

  test "output layout shrinks the status pane" do
    {dashboard, _} = render(layout: :dashboard, width: 40, height: 20)
    {focused, _} = render(layout: :output, width: 40, height: 20)

    assert dashboard =~ "\e[7;1H┌"
    assert focused =~ "\e[5;1H┌"
    refute focused =~ "project: exmex-talk"
    assert focused =~ "tests: idle"
    assert focused =~ "server: down"
  end

  test "help overlay draws a keymap on top of the panes" do
    {output, _} = render(overlay: :help)
    assert output =~ "help"
    assert Termex.ANSI.strip(output) =~ "t  run tests"
    assert output =~ "arrows  scroll output"
    assert output =~ "esc or ? closes"
  end

  test "git overlay draws status text and the git keymap" do
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
    assert output =~ "esc or g closes"
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

  test "fail strip sits between status and output when tests failed" do
    failures = [
      %{
        name: "test Foo.bar/1 (FooTest)",
        file: "test/foo_test.exs",
        line: 12,
        snippet: "Assertion with == failed"
      }
    ]

    {output, state} =
      render(test_state: :fail, failures: failures, width: 40, height: 20)

    layout = Layout.compute(state)
    assert layout.fail.row == 7
    assert layout.output.row == 11
    assert output =~ "fail 1/1"
    assert output =~ "test Foo.bar/1"
    assert output =~ "test/foo_test.exs:12"
  end
end
