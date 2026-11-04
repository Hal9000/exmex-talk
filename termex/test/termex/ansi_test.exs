defmodule Termex.ANSITest do
  use ExUnit.Case, async: false

  alias Termex.ANSI

  setup do
    original = System.get_env("NO_COLOR")

    on_exit(fn ->
      if is_nil(original) do
        System.delete_env("NO_COLOR")
      else
        System.put_env("NO_COLOR", original)
      end
    end)

    System.delete_env("NO_COLOR")
    :ok
  end

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

  test "show_cursor and hide_cursor" do
    assert ANSI.show_cursor() == "\e[?25h"
    assert ANSI.hide_cursor() == "\e[?25l"
  end

  test "bold wraps text and strip drops CSI" do
    assert ANSI.wrap_bold("t") == "\e[1mt\e[0m"
    assert Termex.bold("t") == "\e[1mt\e[0m"
    assert ANSI.strip("\e[1mt\e[0mest") == "test"
    assert ANSI.strip("plain") == "plain"
  end

  test "foreground colors and reverse video wrap text" do
    assert ANSI.foreground(:red) == "\e[31m"
    assert ANSI.reverse() == "\e[7m"
    assert Termex.color("fail", :red) == "\e[31mfail\e[0m"
    assert Termex.reverse("selected") == "\e[7mselected\e[0m"
  end

  test "standard and bright foreground colors use their SGR codes" do
    standard = ~w(black red green yellow blue magenta cyan white)a

    bright =
      ~w(bright_black bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white)a

    assert Enum.map(standard, &ANSI.foreground/1) ==
             Enum.map(30..37, &"\e[#{&1}m")

    assert Enum.map(bright, &ANSI.foreground/1) ==
             Enum.map(90..97, &"\e[#{&1}m")
  end

  test "NO_COLOR presence suppresses color and reverse, even when empty" do
    System.put_env("NO_COLOR", "")

    refute ANSI.color_enabled?()
    assert Termex.color(["f", "ail"], :red) == "fail"
    assert Termex.reverse(["s", "elected"]) == "selected"
  end

  test "color policy can be checked without reading the process environment" do
    assert ANSI.color_enabled?(%{})
    refute ANSI.color_enabled?(%{"NO_COLOR" => "1"})
    assert ANSI.wrap_color("ok", :green, %{}) == "\e[32mok\e[0m"
    assert ANSI.wrap_color("ok", :green, %{"NO_COLOR" => "anything"}) == "ok"
    assert ANSI.wrap_reverse("selected", %{"NO_COLOR" => ""}) == "selected"
  end
end
