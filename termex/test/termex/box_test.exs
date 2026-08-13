defmodule Termex.BoxTest do
  use ExUnit.Case, async: true

  alias Termex.{Box, Capture}

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

  test "titled_edge clips the title to the inner width" do
    edge = Box.titled_edge(10, "status")
    assert String.length(edge) == 10
    assert edge =~ "status"

    short = Box.titled_edge(6, "status")
    assert String.length(short) == 6
    refute short =~ "status"
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
end
