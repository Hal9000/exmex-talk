defmodule Tidex.ScrollTest do
  use ExUnit.Case, async: true

  alias Tidex.Scroll

  @lines Enum.map(1..15, &"row#{&1}")

  test "follow shows the newest lines" do
    assert Scroll.visible(@lines, 10, :follow) == Enum.map(6..15, &"row#{&1}")
  end

  test "a pinned offset shows a window from the start of the log" do
    assert Scroll.visible(@lines, 10, 0) == Enum.map(1..10, &"row#{&1}")
    assert Scroll.visible(@lines, 10, 2) == Enum.map(3..12, &"row#{&1}")
  end

  test "up from follow pins one line above the tail" do
    assert Scroll.step(@lines, 10, :follow, -1) == 4
  end

  test "down from the last pinned row returns to follow" do
    assert Scroll.step(@lines, 10, 4, 1) == :follow
  end

  test "down while following stays on the tail" do
    assert Scroll.step(@lines, 10, :follow, 1) == :follow
  end

  test "up does nothing when the log fits in the pane" do
    short = ["a", "b"]
    assert Scroll.step(short, 10, :follow, -1) == :follow
  end

  test "page up jumps a pane worth of lines and clamps at the top" do
    assert Scroll.step(@lines, 10, :follow, -10) == 0
    assert Scroll.step(@lines, 10, 0, -10) == 0
  end

  test "page down from the top returns to follow when it reaches the tail" do
    assert Scroll.step(@lines, 10, 0, 10) == :follow
  end

  test "title is plain while following and shows a range when pinned" do
    assert Scroll.title(@lines, 10, :follow) == "output"
    assert Scroll.title(@lines, 10, 0) == "output 1-10/15"
    assert Scroll.title(@lines, 10, 4) == "output 5-14/15"
  end
end
