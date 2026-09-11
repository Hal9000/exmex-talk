defmodule Termex.KeysTest do
  use ExUnit.Case, async: true

  alias Termex.Capture

  defp keys(input) do
    {device, _out} = Capture.open(input)
    collect(device, [])
  end

  defp collect(device, acc) do
    case Termex.read_key(device) do
      :eof -> Enum.reverse(acc)
      key -> collect(device, [key | acc])
    end
  end

  test "letters are still one byte at a time" do
    assert keys("tq") == ["t", "q"]
  end

  test "empty input is eof" do
    {device, _out} = Capture.open("")
    assert Termex.read_key(device) == :eof
  end

  test "decodes CSI arrow keys" do
    assert keys("\e[A") == [:up]
    assert keys("\e[B") == [:down]
    assert keys("\e[C") == [:right]
    assert keys("\e[D") == [:left]
  end

  test "decodes SS3 application-mode arrow keys" do
    assert keys("\eOA") == [:up]
    assert keys("\eOB") == [:down]
    assert keys("\eOC") == [:right]
    assert keys("\eOD") == [:left]
  end

  test "decodes page up and page down" do
    assert keys("\e[5~") == [:page_up]
    assert keys("\e[6~") == [:page_down]
  end

  test "a lone ESC is :esc" do
    assert keys("\e") == [:esc]
    assert keys("\e\0") == [:esc]
  end

  test "mixes arrows with ordinary keys" do
    assert keys("t\e[Aq") == ["t", :up, "q"]
  end

  test "skips unknown CSI so it does not leak as characters" do
    assert keys("\e[Zq") == ["q"]
  end

  test "ctrl-c is still a single byte" do
    assert keys(<<3>>) == [<<3>>]
  end
end
