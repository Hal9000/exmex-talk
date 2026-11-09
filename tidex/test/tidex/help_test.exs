defmodule Tidex.HelpTest do
  use ExUnit.Case, async: true

  alias Tidex.{Help, Modal}

  test "help is one 64x18 scrollable document" do
    screen = %{width: 80, height: 24}
    modal = Help.modal(screen)
    pane = Modal.pane(screen, modal)
    visible = Enum.map(modal.lines, &Termex.ANSI.strip/1)
    document = Enum.join(visible, " ")

    assert modal.kind == :help
    assert modal.page == :document
    assert modal.scroll == 0
    assert pane.width == 64
    assert pane.height == 18
    assert hd(visible) == "TESTS"
    assert document =~ "FAILURES"
    assert document =~ "specific project source location"
    assert document =~ "cannot reliably infer"
    assert document =~ "NAVIGATION"

    scrolled = Help.scroll(modal, :down, screen)
    assert scrolled.scroll == 1
  end

  test "help keeps a terminal margin and wraps to its actual inner width" do
    screen = %{width: 42, height: 12}
    modal = Help.modal(screen)
    pane = Modal.pane(screen, modal)

    assert pane.width == 40
    assert pane.height == 10

    assert Enum.all?(modal.lines, fn line ->
             line |> Termex.ANSI.strip() |> String.length() <= 38
           end)
  end
end
