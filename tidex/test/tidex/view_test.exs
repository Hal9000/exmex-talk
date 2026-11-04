defmodule Tidex.ViewTest do
  use ExUnit.Case, async: false

  alias Tidex.{Failures, FakeTerminal, GitModal, Help, Layout, State, View}

  setup do
    original = System.get_env("NO_COLOR")
    System.delete_env("NO_COLOR")

    on_exit(fn ->
      if is_nil(original),
        do: System.delete_env("NO_COLOR"),
        else: System.put_env("NO_COLOR", original)
    end)
  end

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
    assert output =~ "\e[2m"

    {modal_start, _length} = :binary.match(output, "\e[96m")
    modal_output = binary_part(output, modal_start, byte_size(output) - modal_start)
    refute modal_output =~ "\e[2m"

    pane = Tidex.Modal.pane(state, modal)
    assert pane.width < state.width
    assert pane.height < state.height
    inner = Layout.inner(pane)
    rows = FakeTerminal.region_lines(output, inner)
    assert hd(rows) =~ "modal-body-unique"
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
    assert output =~ "\e[7midle   \e[0m"
    assert output =~ "\e[7mdown   \e[0m"
  end

  test "NO_COLOR keeps status alignment without reverse video" do
    System.put_env("NO_COLOR", "1")
    {output, _state} = render(modal: Help.modal())

    refute output =~ "\e[7m"
    refute output =~ "\e[2m"
    refute output =~ "\e[96m"
    visible = Termex.ANSI.strip(output)
    assert visible =~ "t  idle"
    assert visible =~ "s  down"
    assert visible =~ "help"
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

  test "shows aligned reverse-video test and server statuses" do
    {output, _} = render(test_state: :running)
    assert output =~ "\e[7mrunning\e[0m"
    assert Termex.ANSI.strip(output) =~ "t  running  0 fail"

    {output, _} = render(test_state: :pass)
    assert output =~ "\e[7mpass   \e[0m"
    assert Termex.ANSI.strip(output) =~ "t  pass"

    {output, _} = render(test_state: :fail)
    assert output =~ "\e[7mfail   \e[0m"
    assert Termex.ANSI.strip(output) =~ "t  fail"

    {output, _} = render(server_state: :up)
    assert output =~ "\e[7mup     \e[0m"
    assert Termex.ANSI.strip(output) =~ "s  up"
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

  test "lobby shows a fail count, not the failure body" do
    failures = [
      %{name: "test Foo", file: "test/foo_test.exs", line: 12, snippet: "left behind"}
    ]

    {output, _} = render(test_state: :fail, failures: failures)
    visible = Termex.ANSI.strip(output)
    assert output =~ "\e[7mfail   \e[0m"
    assert visible =~ "t  fail     1 fail"
    assert visible =~ "f  fail"
    refute visible =~ "test Foo"
    refute visible =~ "foo_test.exs"
    refute visible =~ "left behind"
  end

  test "help modal draws a selectable topic menu over the lobby" do
    modal = Help.modal()
    {output, state} = render(modal: modal, width: 80, height: 24)
    pane = Tidex.Modal.pane(state, modal)

    assert output =~ "help"
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Tidex · exmex-talk"
    assert visible =~ "> Tests — run and read status"
    assert visible =~ "Failures — inspect and edit"
    assert output =~ "enter open"
    assert output =~ "esc close"
    assert pane.width < state.width
    assert pane.height < state.height
  end

  test "git modal draws status and its keymap over the dimmed lobby" do
    git = %{
      branch: "main",
      dirty: 1,
      status: "On branch main\nChanges not staged for commit:\n  modified: lib/tidex.ex"
    }

    state = %State{git: git, width: 80, height: 24}
    modal = GitModal.modal(state)
    {output, state} = render(git: git, modal: modal, width: 80, height: 24)
    pane = Tidex.Modal.pane(state, modal)

    assert Termex.ANSI.strip(output) =~ "Tidex · exmex-talk"
    assert output =~ "git"
    assert Termex.ANSI.strip(output) =~ "add -u"
    assert output =~ "On branch main"
    assert output =~ "modified: lib/tidex.ex"
    assert Termex.ANSI.strip(output) =~ "esc close"
    assert pane.width == 60
    assert pane.width < state.width
    assert pane.height < state.height
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
    assert visible =~ "t  fail     1 fail"
    assert visible =~ "f  fail"
    refute visible =~ "test Foo.bar/1"
    refute visible =~ "Assertion with == failed"
    refute output =~ "test · fail"
  end

  test "the failure box sits on the lobby at 60x8 with a command footer" do
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
    assert visible =~ "t  fail     1 fail"
    assert visible =~ "test Foo.bar/1 (FooTest)"
    assert visible =~ "test/foo_test.exs:12"
    assert visible =~ "Assertion with == failed"
    assert visible =~ "fail 1/1"
    assert visible =~ "edit"

    pane = Tidex.Modal.pane(state, modal)
    assert pane.width == 60
    assert pane.height == 8
    inner = Layout.inner(pane)
    rows = FakeTerminal.region_lines(output, inner)
    assert hd(rows) =~ "test Foo.bar/1"
    assert Enum.at(rows, 1) =~ "foo_test.exs:12"
  end
end
