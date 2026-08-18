defmodule Tidex.ModalTest do
  use ExUnit.Case, async: true

  alias Tidex.{FakeTerminal, Layout, Modal}

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
    # 2 body rows + commands + 2 borders = 5
    assert pane.height == 5
    assert pane.width < 80
    assert pane.height < 24
  end

  test "centers on the screen" do
    modal = %Modal{lines: ["hi"], commands: "esc", max_width: 50, max_height: 10}
    pane = Modal.pane(screen(40, 20), modal)
    # inner width 3 ("esc"), outer 5; height 1 body + commands + 2 borders = 4
    assert pane.width == 5
    assert pane.height == 4
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

  test "writes the title on the top edge" do
    modal = %Modal{title: "demo", lines: ["body"], commands: "esc"}
    {out, _pane} = draw(modal)
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
    assert List.last(rows) =~ "esc"
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
