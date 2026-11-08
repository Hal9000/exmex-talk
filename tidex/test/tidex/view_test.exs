defmodule Tidex.ViewTest do
  use ExUnit.Case, async: false

  alias Tidex.{Failures, FakeTerminal, GitModal, Help, Layout, LobbyLayout, State, View}

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
        %State{
          width: 80,
          height: 24,
          project_name: "exmex-talk",
          server_command: "server",
          browser_url: "http://localhost:4000"
        },
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
    assert visible =~ "Run tests"
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

  test "lobby draws nested quadrants and no output lake" do
    {output, _state} = render([])

    assert output =~ "\e[?25l"
    assert output =~ "\e[2J"
    assert output =~ "┌"
    assert output =~ "└"
    assert output =~ "Tidex · exmex-talk"
    refute output =~ "output"
    refute output =~ "project:"
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Edit files"
    assert visible =~ "Run tests"
    assert visible =~ "Step through failures"
    assert visible =~ "Start/restart"
    assert visible =~ "Stop"
    assert visible =~ "Browse"
    assert visible =~ "More information"
    assert visible =~ "Open full pane"
    assert visible =~ "0  tidex.conf"
    assert visible =~ "?  help"
    assert visible =~ "q  quit"
    refute visible =~ "xstop"
    refute visible =~ "?help"
    refute visible =~ "idle"
    refute output =~ "\e[7m" <> "idle"
    assert output =~ "\e[7mdown\e[0m"
    assert output =~ "\e[1mt\e[0m"
    refute visible =~ "t  down"
  end

  test "NO_COLOR keeps commands plain without reverse on key rows" do
    System.put_env("NO_COLOR", "1")
    {output, _state} = render(modal: Help.modal())

    refute output =~ "\e[7m"
    refute output =~ "\e[2m"
    refute output =~ "\e[96m"
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Run tests"
    assert visible =~ "down"
    assert visible =~ "help"
  end

  test "lobby is content-height, capped at 80 columns, and centered" do
    files = %{1 => "README.md", 2 => "lib/proj1.ex", 3 => "test/proj1_test.exs"}
    git = %{branch: "main", dirty: 3, untracked: 2}
    {output, _state} = render(width: 140, height: 40, files: files, git: git)

    rows = LobbyLayout.content_rows(%State{})
    pane = LobbyLayout.lobby(140, 40, rows)
    assert pane.width == 80
    assert pane.height == rows + 2
    assert output =~ "Tidex · exmex-talk"
    assert output =~ "Edit files"
    assert output =~ "dirty"
  end

  test "puts short test status in the title and long status on the bottom line" do
    {output, _} = render(test_state: :running)
    assert output =~ "\e[7mRunning\e[0m"
    refute output =~ "\e[7mrunning\e[0m"

    {output, _} = render(test_state: :pass)
    assert output =~ "\e[7mpass"
    refute output =~ "\e[7mRunning\e[0m"

    {output, _} =
      render(test_state: :fail, failures: [%{name: "x", file: nil, line: nil, snippet: ""}])

    assert output =~ "\e[7mFail\e[0m"
    assert output =~ "\e[7m1 fail"
  end

  test "server status is always in the title bar" do
    {output, _} = render(server_state: :up)
    assert output =~ "\e[7mup\e[0m"
    refute visible_command_status(output, "s", "up")
  end

  test "git title omits status when clean" do
    {output, _} = render(git: %{branch: "main", dirty: 0, untracked: 0})
    refute output =~ "\e[7mmain\e[0m"
    assert Termex.ANSI.strip(output) =~ "Open full pane"

    {output, _} = render(git: %{branch: "main", dirty: 3, untracked: 2})
    assert output =~ "dirty"
    refute Termex.ANSI.strip(output) =~ "main"
  end

  test "lists file1-file4 on the lobby and omits missing slots" do
    {output, _} = render(files: %{1 => "README.md", 3 => "lib/tidex.ex"})
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Edit files"
    assert visible =~ "1  README.md"
    assert visible =~ "3  lib/tidex.ex"
    refute visible =~ "2  "
  end

  test "always lists 0 tidex.conf under Edit files" do
    {output, _} = render(files: %{})
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Edit files"
    assert visible =~ "0  tidex.conf"
    refute visible =~ "1  "
  end

  test "keeps the server box but replaces disabled controls when unconfigured" do
    {output, _state} = render(server_command: nil, browser_url: nil)
    visible = Termex.ANSI.strip(output)

    assert visible =~ "Server"
    assert visible =~ "[No server configured]"
    refute visible =~ "Start/restart"
    refute visible =~ "Stop"
    refute visible =~ "Browse"
  end

  test "lobby shows fail count on the long status line, not the failure body" do
    failures = [
      %{name: "test Foo", file: "test/foo_test.exs", line: 12, snippet: "left behind"}
    ]

    {output, _} = render(test_state: :fail, failures: failures)
    visible = Termex.ANSI.strip(output)
    assert output =~ "\e[7mFail\e[0m"
    assert visible =~ "1 fail"
    assert visible =~ "Step through failures"
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
    assert visible =~ "Run tests"
    assert visible =~ "> Tests — run and read status"
    assert output =~ "enter open"
    assert output =~ "esc close"
    assert pane.width < state.width
    assert pane.height < state.height
  end

  test "git modal fixes its command menu above scrollable status and a footer" do
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
    visible = Termex.ANSI.strip(output)
    assert visible =~ "Add tracked changes"
    assert visible =~ "Pull (fast-forward only)"
    assert visible =~ "Ship (add, commit, rebase, push)"
    assert output =~ "On branch main"
    assert output =~ "modified: lib/tidex.ex"
    assert visible =~ "pgup/pgdn scroll"
    assert visible =~ "esc close"
    assert pane.width == 60
    assert pane.height >= 15
    assert pane.width < state.width
    assert pane.height < state.height
  end

  test "setup draws a modal over the dimmed lobby with commands inside" do
    setup = %Tidex.Setup{
      cwd: "/tmp/demo-project",
      git_root: nil,
      offer_cwd: true,
      offer_git: false
    }

    modal = Tidex.Setup.modal(setup)
    {output, state} = render(overlay: :setup, setup: setup, width: 80)
    pane = Tidex.Modal.pane(state, modal)

    assert output =~ "Tidex · exmex-talk"
    assert output =~ "tidex.conf"
    assert output =~ "no tidex.conf"
    assert output =~ "write in cwd"
    assert Termex.ANSI.strip(output) =~ "y write here"
    assert output =~ "\e[2m"
    assert output =~ "\e[96m"
    assert pane.width < state.width
    assert pane.height < state.height
  end

  test "setup modal states that a blocked cwd is not permitted" do
    setup = %Tidex.Setup{cwd: "/tmp", blocked: true, offer_cwd: false}
    {output, _} = render(overlay: :setup, setup: setup, width: 80)
    assert output =~ "cwd is not permitted"
    assert output =~ "/tmp"
    refute Termex.ANSI.strip(output) =~ "y write here"
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
        output_lines: ["1) test Foo.bar/1 (FooTest)", "Assertion with == failed"]
      )

    visible = Termex.ANSI.strip(output)
    assert visible =~ "1 fail"
    assert visible =~ "Step through failures"
    refute visible =~ "test Foo.bar/1"
    refute visible =~ "Assertion with == failed"
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
    assert visible =~ "1 fail"
    assert visible =~ "test Foo.bar/1"
    refute visible =~ "(FooTest)"
    assert visible =~ "FooTest test/foo_test.exs:12"
    assert visible =~ "Assertion with == failed"
    assert visible =~ "fail 1/1"
    assert visible =~ "edit"

    pane = Tidex.Modal.pane(state, modal)
    assert pane.width == 60
    assert pane.height == 8
    inner = Layout.inner(pane)
    rows = FakeTerminal.region_lines(output, inner)
    assert hd(rows) =~ "test Foo.bar/1"
    assert Enum.at(rows, 1) =~ "FooTest test/foo_test.exs:12"
  end

  defp visible_command_status(output, letter, status) do
    Termex.ANSI.strip(output) =~ "#{letter}  #{status}"
  end
end
