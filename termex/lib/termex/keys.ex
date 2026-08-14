defmodule Termex.Keys do
  @moduledoc """
  Turns a byte stream into keys.

  Printable (and other single-byte) input stays a one-byte string.
  Arrow and page keys become atoms. A lone ESC is `:esc`. Unknown CSI
  sequences are skipped so they do not leak as garbage characters.
  """

  @esc "\e"

  @type t ::
          String.t()
          | :eof
          | :esc
          | :up
          | :down
          | :left
          | :right
          | :page_up
          | :page_down

  @spec read(IO.device()) :: t()
  def read(input) do
    case read_byte(input) do
      :eof -> :eof
      @esc -> read_escape(input)
      byte -> byte
    end
  end

  defp read_escape(input) do
    case read_follow(input) do
      :eof ->
        :esc

      "[" ->
        case read_csi(input, "") do
          :unknown -> read(input)
          :incomplete -> :esc
          key -> key
        end

      "O" ->
        case read_byte(input) do
          "A" -> :up
          "B" -> :down
          "C" -> :right
          "D" -> :left
          :eof -> :esc
          _ -> read(input)
        end

      _other ->
        _other
    end
  end

  defp read_csi(_input, acc) when byte_size(acc) > 16, do: :unknown

  defp read_csi(input, acc) do
    case read_byte(input) do
      :eof ->
        :incomplete

      byte ->
        acc = acc <> byte

        if csi_final?(byte) do
          decode_csi(acc)
        else
          read_csi(input, acc)
        end
    end
  end

  defp csi_final?(<<c>>) when c in 0x40..0x7E, do: true
  defp csi_final?(_), do: false

  defp decode_csi("A"), do: :up
  defp decode_csi("B"), do: :down
  defp decode_csi("C"), do: :right
  defp decode_csi("D"), do: :left
  defp decode_csi("5~"), do: :page_up
  defp decode_csi("6~"), do: :page_down
  defp decode_csi(_), do: :unknown

  defp read_follow(input) do
    if tty_input?(input) do
      briefly_nonblocking(fn -> read_byte(input) end)
    else
      read_byte(input)
    end
  end

  defp tty_input?(input) when input in [:stdio, :standard_io], do: true
  defp tty_input?(_), do: false

  # After ESC, wait up to 100ms for the rest of a CSI/SS3 sequence so a
  # lone Escape key can still be distinguished from an arrow. Arrow bytes
  # are already in the kernel buffer; this timeout is only for ESC.
  defp briefly_nonblocking(fun) do
    System.cmd("stty", ["-icanon", "-echo", "min", "0", "time", "1"], stderr_to_stdout: true)

    try do
      fun.()
    after
      System.cmd("stty", ["-icanon", "-echo", "min", "1", "time", "0"], stderr_to_stdout: true)
    end
  end

  defp read_byte(input) do
    case IO.getn(input, "", 1) do
      :eof -> :eof
      {:error, _} -> :eof
      "" -> :eof
      key when is_binary(key) and byte_size(key) > 0 -> key
      [char] when is_integer(char) -> <<char>>
      _ -> :eof
    end
  end
end
