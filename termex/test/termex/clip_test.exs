defmodule Termex.ClipTest do
  use ExUnit.Case, async: true

  alias Termex.Capture

  test "clip/2 truncates to width and treats newlines as spaces" do
    assert Termex.clip("hello world", 5) == "hello"
    assert Termex.clip("ab\ncd", 5) == "ab cd"
    assert Termex.clip("hello", 0) == ""
    assert Termex.clip("hi", 10) == "hi"
  end

  test "write_clipped does not emit characters past width" do
    {device, out} = Capture.open()
    assert :ok = Termex.write_clipped(device, 1, 1, 4, "hello world")
    assert Capture.text(out) == "\e[1;1Hhell"
  end

  test "write_region keeps text inside height and width" do
    {device, out} = Capture.open()
    assert :ok = Termex.write_region(device, 2, 3, 4, 2, ["abcdef", "ghijkl", "dropped"])
    text = Capture.text(out)

    assert text =~ "\e[2;3Habcd"
    assert text =~ "\e[3;3Hghij"
    refute text =~ "dropped"
    refute text =~ "ef"
    refute text =~ "kl"
  end

  test "clip/2 ignores CSI when counting width and closes SGR" do
    assert Termex.clip("\e[1mhello", 5) == "\e[1mhello\e[0m"
    assert Termex.clip("\e[1mhello\e[0m", 5) == "\e[1mhello\e[0m"
    assert Termex.clip("\e[1mhello\e[0m world", 5) == "\e[1mhello\e[0m"
    assert Termex.clip("\e[1mab\e[0mcd", 3) == "\e[1mab\e[0mc"
    assert Termex.clip(Termex.bold("foobar"), 3) == "\e[1mfoo\e[0m"
    assert Termex.clip("hello", 5) == "hello"
  end
end
