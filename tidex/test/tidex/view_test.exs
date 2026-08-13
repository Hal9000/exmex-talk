defmodule Tidex.ViewTest do
  use ExUnit.Case, async: true

  alias Tidex.{FakeTerminal, State, View}

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

  test "draws a two-pane layout with status and output boxes" do
    {output, _state} = render([])

    assert output =~ "\e[2J"
    assert output =~ "┌"
    assert output =~ "└"
    assert output =~ "status"
    assert output =~ "output"
    assert output =~ "project: exmex-talk"
    assert output =~ "tests:   idle"
    assert output =~ "server:  idle"
    assert output =~ "[t] test"
    assert output =~ "[s] server"
    assert output =~ "[q] quit"
  end

  test "shows test state in the status pane" do
    {output, _} = render(test_state: :running)
    assert output =~ "tests:   running"

    {output, _} = render(test_state: :pass)
    assert output =~ "tests:   pass"

    {output, _} = render(test_state: :fail)
    assert output =~ "tests:   fail"
  end

  test "displays command output inside the output pane" do
    {output, _} = render(output_lines: ["hello from tests"])
    assert output =~ "hello from tests"
  end

  test "clips output that would overflow the pane" do
    long = "KEEP_START" <> String.duplicate("x", 80) <> "KEEP_END"
    {output, _} = render(width: 24, height: 16, output_lines: [long])

    assert output =~ "KEEP_START"
    refute output =~ "KEEP_END"
  end

  test "output pane keeps the latest lines when they overflow height" do
    lines = Enum.map(1..20, &"row#{&1}-end")
    {output, _} = render(width: 40, height: 12, output_lines: lines)

    assert output =~ "row20-end"
    refute output =~ "row1-end"
  end
end
