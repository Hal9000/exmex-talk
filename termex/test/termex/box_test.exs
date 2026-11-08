defmodule Termex.BoxTest do
  use ExUnit.Case, async: false

  alias Termex.{Box, Capture}

  setup do
    original = System.get_env("NO_COLOR")
    System.delete_env("NO_COLOR")

    on_exit(fn ->
      if is_nil(original),
        do: System.delete_env("NO_COLOR"),
        else: System.put_env("NO_COLOR", original)
    end)
  end

  test "horizontal/1 repeats the line character" do
    assert Box.horizontal(5) == "─────"
    assert Box.horizontal(0) == ""
  end

  test "corners are the light box-drawing set" do
    assert Box.corner(:top_left) == "┌"
    assert Box.corner(:top_right) == "┐"
    assert Box.corner(:bottom_left) == "└"
    assert Box.corner(:bottom_right) == "┘"
  end

  test "junctions connect an interior horizontal divider" do
    assert Box.junction(:left) == "├"
    assert Box.junction(:right) == "┤"
  end

  test "titled_edge clips the title to the inner width" do
    edge = Box.titled_edge(10, "status")
    assert String.length(edge) == 10
    assert edge =~ "status"

    short = Box.titled_edge(6, "status")
    assert String.length(short) == 6
    refute short =~ "status"
  end

  test "titled_edge keeps a styled title the full visible width" do
    edge = Box.titled_edge(20, "git ─ " <> Termex.reverse("dirty"))
    visible = Termex.ANSI.strip(edge)
    assert String.length(visible) == 20
    assert String.ends_with?(visible, "─")
    assert visible =~ "dirty"
  end

  test "hline writes a horizontal run at the cursor" do
    {device, out} = Capture.open()
    assert :ok = Termex.hline(device, 2, 3, 4)
    assert Capture.text(out) == "\e[2;3H────"
  end

  test "vline writes one character per row" do
    {device, out} = Capture.open()
    assert :ok = Termex.vline(device, 1, 2, 3)
    text = Capture.text(out)
    assert text =~ "\e[1;2H│"
    assert text =~ "\e[2;2H│"
    assert text =~ "\e[3;2H│"
  end

  test "corner writes a single corner glyph" do
    {device, out} = Capture.open()
    assert :ok = Termex.corner(device, 1, 1, :top_left)
    assert Capture.text(out) == "\e[1;1H┌"
  end

  test "box draws corners, edges, and a title" do
    {device, out} = Capture.open()
    assert :ok = Termex.box(device, 1, 1, 12, 4, title: "status")
    text = Capture.text(out)

    assert text =~ "┌"
    assert text =~ "┐"
    assert text =~ "└"
    assert text =~ "┘"
    assert text =~ "│"
    assert text =~ "─"
    assert text =~ "status"
  end

  test "box can color only its frame and title" do
    {device, out} = Capture.open()
    assert :ok = Termex.box(device, 1, 1, 12, 4, title: "status", frame_color: :bright_cyan)
    text = Capture.text(out)

    assert text =~ "\e[96m┌\e[0m"
    assert text =~ "\e[96m─ status "
    assert text =~ "\e[96m│\e[0m"
    assert Termex.ANSI.strip(text) =~ "status"
  end

  test "NO_COLOR suppresses box frame color" do
    System.put_env("NO_COLOR", "1")
    {device, out} = Capture.open()
    assert :ok = Termex.box(device, 1, 1, 12, 4, title: "status", frame_color: :bright_cyan)

    refute Capture.text(out) =~ "\e[96m"
  end

  test "box divider draws colored junctions and a horizontal rule" do
    {device, out} = Capture.open()
    assert :ok = Termex.box_divider(device, 3, 2, 8, frame_color: :bright_cyan)

    assert Capture.text(out) == "\e[3;2H\e[96m├──────┤\e[0m"
  end
end
