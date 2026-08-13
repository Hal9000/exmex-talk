defmodule Tidex.ViewTest do
  use ExUnit.Case, async: true

  alias Tidex.{FakeTerminal, State, View}

  test "renders title, project name, and status labels through Termex" do
    {device, out} = FakeTerminal.open()
    state = %State{title: "Tidex", project_name: "exmex-talk"}

    assert :ok = View.render(device, state)
    output = FakeTerminal.text(out)

    assert output =~ "\e[2J"
    assert output =~ "\e[1;1H"
    assert output =~ "Tidex"
    assert output =~ "project: exmex-talk"
    assert output =~ "tests:"
    assert output =~ "idle"
    assert output =~ "git:"
    assert output =~ "[t] run command"
    assert output =~ "[q] quit"
  end

  test "renders captured command output" do
    {device, out} = FakeTerminal.open()
    state = %State{command_output: "hello from tidex\n"}

    View.render(device, state)
    assert FakeTerminal.text(out) =~ "hello from tidex"
  end
end
