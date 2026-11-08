defmodule Tidex.OutputModalTest do
  use ExUnit.Case, async: true

  alias Tidex.OutputModal

  test "builds test and server output views" do
    test_modal = OutputModal.modal(:test, ["compile failed"])
    assert test_modal.kind == :output
    assert test_modal.page == :test
    assert test_modal.title == "test failure output"
    assert test_modal.lines == ["compile failed"]

    server_modal = OutputModal.modal(:server, [])
    assert server_modal.page == :server
    assert server_modal.title == "server output"
    assert server_modal.lines == ["(no output)"]
  end

  test "scrolls independently through long output" do
    modal = OutputModal.modal(:test, Enum.map(1..30, &"line #{&1}"))
    screen = %{width: 80, height: 24}

    modal = OutputModal.scroll(modal, :up, screen)
    assert is_integer(modal.scroll)

    page = OutputModal.scroll(modal, :page_up, screen)
    assert page.scroll < modal.scroll
  end
end
