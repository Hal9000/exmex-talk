defmodule Tidex.HelpTest do
  use ExUnit.Case, async: true

  alias Tidex.{Help, Modal}

  test "menu is a fixed-size selectable topic list" do
    modal = Help.modal()
    pane = Modal.pane(%{width: 80, height: 24}, modal)
    visible = Enum.map(modal.lines, &Termex.ANSI.strip/1)

    assert modal.kind == :help
    assert modal.page == :menu
    assert modal.selection == 0
    assert hd(visible) =~ "> Tests — run and read status"
    assert Enum.at(visible, 1) =~ "Failures — inspect and edit"
    assert pane.width == 50
    assert pane.height == 10

    moved = Help.move(modal, -1)
    assert moved.selection == 5
    assert List.last(moved.lines) |> Termex.ANSI.strip() =~ "> Navigation"
  end

  test "opening a topic replaces the menu with wrapped, scrollable prose" do
    modal = Help.modal() |> Help.move(1) |> Help.open()

    assert modal.page == {:topic, :failures}
    assert modal.title == "help · Failures"
    assert length(modal.lines) > 7
    assert Enum.all?(modal.lines, &(String.length(&1) <= 46))
    assert Enum.join(modal.lines, " ") =~ "configured editor"

    scrolled = Help.scroll(modal, :down, %{width: 80, height: 24})
    assert scrolled.scroll == 1

    menu = Help.back(scrolled)
    assert menu.page == :menu
    assert menu.selection == 1
  end
end
