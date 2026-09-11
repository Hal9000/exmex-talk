defmodule Termex.Keys do
  @moduledoc """
  Turns a byte stream into keys.

  Printable (and other single-byte) input stays a one-byte string.
  Arrow and page keys become atoms. A lone ESC is `:esc`. Unknown CSI
  sequences are skipped so they do not leak as garbage characters.
  """

  @esc "\e"
  @buffer_key {__MODULE__, :input_buffer}

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

      <<0>> ->
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

      other ->
        other
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
      buffered_byte()
    else
      read_byte(input)
    end
  end

  defp tty_input?(input) when input in [:stdio, :standard_io], do: true
  defp tty_input?(_), do: false

  # OTP's native raw terminal returns all bytes currently available. Keep
  # the rest in this keyboard process so ESC can be classified without a
  # second blocking read.
  defp read_byte(input) when input in [:stdio, :standard_io] do
    case buffered_byte() do
      :eof ->
        input
        |> IO.getn("", 1024)
        |> buffer_chunk()

        buffered_byte()

      byte ->
        byte
    end
  end

  defp read_byte(input), do: input |> IO.getn("", 1) |> normalize_byte()

  defp buffer_chunk(result) do
    case normalize_chunk(result) do
      "" -> Process.delete(@buffer_key)
      chunk -> Process.put(@buffer_key, chunk)
    end
  end

  defp buffered_byte do
    case Process.get(@buffer_key, "") do
      <<byte::binary-size(1), rest::binary>> ->
        if rest == "", do: Process.delete(@buffer_key), else: Process.put(@buffer_key, rest)
        byte

      _ ->
        :eof
    end
  end

  defp normalize_chunk(:eof), do: ""
  defp normalize_chunk({:error, _}), do: ""
  defp normalize_chunk(chunk) when is_binary(chunk), do: chunk
  defp normalize_chunk(chunk) when is_list(chunk), do: IO.iodata_to_binary(chunk)
  defp normalize_chunk(_), do: ""

  defp normalize_byte(:eof), do: :eof
  defp normalize_byte({:error, _}), do: :eof
  defp normalize_byte(""), do: :eof
  defp normalize_byte(key) when is_binary(key) and byte_size(key) > 0, do: key
  defp normalize_byte([char]) when is_integer(char), do: <<char>>
  defp normalize_byte(_), do: :eof
end
