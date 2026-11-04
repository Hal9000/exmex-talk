defmodule TermexTest do
  use ExUnit.Case, async: true

  alias Termex.Capture

  describe "drawing" do
    test "clear_visible writes CSI 2J to the output device" do
      {device, out} = Capture.open()
      assert :ok = Termex.clear_visible(device)
      assert Capture.text(out) == "\e[2J"
    end

    test "move writes a cursor-position sequence" do
      {device, out} = Capture.open()
      assert :ok = Termex.move(device, 3, 5)
      assert Capture.text(out) == "\e[3;5H"
    end

    test "write sends the given text with no extra escapes" do
      {device, out} = Capture.open()
      assert :ok = Termex.write(device, "hello")
      assert Capture.text(out) == "hello"
    end

    test "hide_cursor and show_cursor write visibility sequences" do
      {device, out} = Capture.open()
      assert :ok = Termex.hide_cursor(device)
      assert :ok = Termex.show_cursor(device)
      assert Capture.text(out) == "\e[?25l\e[?25h"
    end

    test "write_at moves then writes" do
      {device, out} = Capture.open()
      assert :ok = Termex.write_at(device, 2, 4, "Tidex")
      assert Capture.text(out) == "\e[2;4HTidex"
    end
  end

  describe "read_key/1" do
    test "returns one character at a time" do
      {device, _out} = Capture.open("tq")
      assert Termex.read_key(device) == "t"
      assert Termex.read_key(device) == "q"
      assert Termex.read_key(device) == :eof
    end

    test "returns eof on empty input" do
      {device, _out} = Capture.open("")
      assert Termex.read_key(device) == :eof
    end
  end

  describe "with_raw_mode/2" do
    test "is a no-op for injected devices and returns the function result" do
      {device, _out} = Capture.open()
      assert Termex.with_raw_mode(device, fn -> :drew end) == :drew
    end

    test "passes a nil session to arity-1 callbacks without a TTY" do
      {device, _out} = Capture.open()
      assert Termex.with_raw_mode(device, fn session -> session end) == nil
    end
  end

  describe "yield/3" do
    test "runs the callback and clears the screen so an editor can take over" do
      {device, out} = Capture.open()
      result = Termex.yield(device, nil, fn -> :edited end)
      assert result == :edited
      text = Capture.text(out)
      assert text =~ "\e[?25h"
      assert text =~ "\e[2J"
    end
  end
end
