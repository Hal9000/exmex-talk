defmodule Termex.ANSITest do
  use ExUnit.Case, async: true

  alias Termex.ANSI

  describe "clear_visible/0" do
    test "returns CSI 2J and does not home the cursor" do
      assert ANSI.clear_visible() == "\e[2J"
      refute ANSI.clear_visible() =~ "H"
    end
  end

  describe "cursor/2" do
    test "returns a 1-based CSI H sequence" do
      assert ANSI.cursor(1, 1) == "\e[1;1H"
      assert ANSI.cursor(4, 10) == "\e[4;10H"
    end
  end
end
