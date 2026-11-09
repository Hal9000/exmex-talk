defmodule Tidex.ModalTest do
  use ExUnit.Case, async: false

  alias Tidex.{FakeTerminal, Layout, Modal}

  setup do
    original = System.get_env("NO_COLOR")
    System.delete_env("NO_COLOR")

    on_exit(fn ->
      if is_nil(original),
        do: System.delete_env("NO_COLOR"),
        else: System.put_env("NO_COLOR", original)
    end)
  end

  defp screen(w, h), do: %{width: w, height: h}

  defp draw(modal, w \\ 40, h \\ 20) do
    {device, out} = FakeTerminal.open()
    assert :ok = Modal.draw(device, screen(w, h), modal)
    {out, Modal.pane(screen(w, h), modal)}
  end

  test "sizes to the content and stays under max_* and the screen" do
    modal = %Modal{
      title: "demo",
      lines: ["hi", "there"],
      commands: "esc",
      max_width: 50,
      max_height: 10
    }

    pane = Modal.pane(screen(80, 24), modal)
    # inner width = max("there"=5, "esc"=3, title "demo"+3=7) = 7 → outer 9
    assert pane.width == 9
    # 2 body rows + divider + commands + 2 borders = 6
    assert pane.height == 6
    assert pane.width < 80
    assert pane.height < 24
  end

  test "centers on the screen" do
    modal = %Modal{lines: ["hi"], commands: "esc", max_width: 50, max_height: 10}
    pane = Modal.pane(screen(40, 20), modal)
    # inner width 3 ("esc"), outer 5; height 1 body + divider + commands + 2 borders = 5
    assert pane.width == 5
    assert pane.height == 5
    assert pane.row == div(20 - pane.height, 2) + 1
    assert pane.col == div(40 - pane.width, 2) + 1
  end

  test "caps a tall body at max_height and still keeps the command row" do
    lines = Enum.map(1..20, &"line #{&1}")
    modal = %Modal{lines: lines, commands: "esc back", max_width: 20, max_height: 6}
    pane = Modal.pane(screen(80, 24), modal)
    assert pane.height == 6
    inner = Layout.inner(pane)

    {out, _} = draw(modal, 80, 24)
    rows = FakeTerminal.region_lines(out, inner)
    assert length(rows) == inner.height
    assert List.last(rows) =~ "esc back"
    assert hd(rows) =~ "line 1"
    refute Enum.any?(rows, &String.contains?(&1, "line 20"))
  end

  test "scroll selects a later body window while keeping the command row" do
    modal = %Modal{
      lines: Enum.map(1..10, &"line #{&1}"),
      commands: "esc back",
      scroll: 2,
      max_width: 20,
      max_height: 6
    }

    {out, pane} = draw(modal, 80, 24)
    rows = FakeTerminal.region_lines(out, Layout.inner(pane))

    assert hd(rows) =~ "line 3"
    assert Enum.at(rows, 1) =~ "line 4"
    assert List.last(rows) =~ "esc back"
    refute Enum.any?(rows, &String.contains?(&1, "line 1"))
  end

  test "keeps top lines fixed above a separately scrolling body" do
    modal = %Modal{
      top_lines: ["a  command", ""],
      lines: Enum.map(1..6, &"status #{&1}"),
      commands: "esc close",
      scroll: 2,
      min_width: 20,
      max_width: 20,
      min_height: 8,
      max_height: 8
    }

    {out, pane} = draw(modal, 80, 24)
    inner = Layout.inner(pane)
    rows = FakeTerminal.region_lines(out, inner)
    top_divider_row = inner.row + 2

    assert Enum.at(rows, 0) =~ "a  command"
    assert Enum.at(rows, 3) =~ "status 3"
    assert FakeTerminal.visible(out) =~ "esc close"
    assert Modal.body_height(screen(80, 24), modal) == 1
    assert FakeTerminal.text(out) =~ "\e[#{top_divider_row};#{pane.col}H\e[96m╟"
  end

  test "draws the command hints in a separated one-line footer" do
    modal = %Modal{title: "demo", lines: ["body"], commands: "esc close"}
    {out, pane} = draw(modal)
    text = FakeTerminal.text(out)
    inner = Layout.inner(pane)
    divider_row = inner.row + inner.height - 2
    command_row = inner.row + inner.height - 1

    assert text =~ "\e[#{divider_row};#{pane.col}H\e[96m╟"
    assert text =~ "╢\e[0m"
    assert text =~ "\e[#{command_row};#{inner.col}H\e[96mesc close\e[0m"
  end

  test "centers command hints within the footer" do
    modal = %Modal{
      title: "demo",
      lines: ["body"],
      commands: "esc",
      min_width: 20,
      max_width: 20
    }

    {out, pane} = draw(modal)
    inner = Layout.inner(pane)
    command_row = inner.row + inner.height - 1
    offset = div(inner.width - String.length("esc"), 2)

    assert FakeTerminal.text(out) =~ "\e[#{command_row};#{inner.col + offset}H\e[96mesc\e[0m"
  end

  test "footer color survives a bold key reset" do
    modal = %Modal{
      title: "demo",
      lines: ["body"],
      commands: Termex.bold("e") <> "  edit",
      min_width: 20,
      max_width: 20
    }

    {out, _pane} = draw(modal)

    assert FakeTerminal.text(out) =~ "\e[96m\e[1me\e[0m\e[96m  edit\e[0m"
  end

  test "clips a long body line to the inner width" do
    modal = %Modal{
      lines: ["KEEP_START" <> String.duplicate("x", 80) <> "KEEP_END"],
      commands: "esc",
      max_width: 16,
      max_height: 6
    }

    {out, pane} = draw(modal, 40, 20)
    inner = Layout.inner(pane)
    [body | _] = FakeTerminal.region_lines(out, inner)
    assert String.contains?(body, "KEEP_START")
    refute String.contains?(body, "KEEP_END")
    assert String.length(Termex.ANSI.strip(body)) <= inner.width
  end

  test "colors the frame and title without coloring the body" do
    modal = %Modal{title: "demo", lines: ["body"], commands: "esc"}
    {out, _pane} = draw(modal)
    text = FakeTerminal.text(out)

    assert FakeTerminal.visible(out) =~ "demo"
    assert text =~ "\e[96m╔\e[0m"
    assert text =~ "\e[96m═ demo "
    refute text =~ "\e[96mbody"
  end

  test "NO_COLOR leaves the modal frame uncolored" do
    System.put_env("NO_COLOR", "1")
    modal = %Modal{title: "demo", lines: ["body"], commands: "esc"}
    {out, _pane} = draw(modal)

    refute FakeTerminal.text(out) =~ "\e[96m"
    assert FakeTerminal.visible(out) =~ "demo"
  end

  test "blanks the interior so the screen underneath does not bleed through" do
    {device, out} = FakeTerminal.open()
    screen = screen(40, 16)
    modal = %Modal{title: "demo", lines: ["only"], commands: "esc", max_width: 20, max_height: 6}
    pane = Modal.pane(screen, modal)
    inner = Layout.inner(pane)

    for row <- inner.row..(inner.row + inner.height - 1) do
      Termex.write_at(device, row, inner.col, String.duplicate("Z", inner.width))
    end

    assert :ok = Modal.draw(device, screen, modal)
    rows = FakeTerminal.region_lines(out, inner)
    refute Enum.any?(rows, &String.contains?(&1, "Z"))
    assert hd(rows) =~ "only"
    assert FakeTerminal.visible(out) =~ "esc"
  end

  test "min_width and min_height pin a small body on a large screen" do
    modal = %Modal{
      lines: ["hi"],
      commands: "esc",
      min_width: 60,
      max_width: 60,
      min_height: 7,
      max_height: 7
    }

    pane = Modal.pane(screen(80, 24), modal)
    assert pane.width == 60
    assert pane.height == 7
    assert pane.row == div(24 - 7, 2) + 1
    assert pane.col == div(80 - 60, 2) + 1
  end
end
