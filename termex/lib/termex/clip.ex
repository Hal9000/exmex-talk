defmodule Termex.Clip do
  @moduledoc false

  @esc ?\e
  @csi ?[
  @final_min ?@
  @final_max ?~

  @spec visible(iodata(), non_neg_integer()) :: String.t()
  def visible(_text, width) when width <= 0, do: ""

  def visible(text, width) do
    text
    |> IO.iodata_to_binary()
    |> String.replace("\n", " ")
    |> take(width, "", false)
  end

  defp take(<<>>, _width, acc, attr), do: finish(acc, attr)
  defp take(_rest, 0, acc, attr), do: finish(acc, attr)

  defp take(<<@esc, @csi, rest::binary>>, width, acc, attr) do
    case csi(rest, "") do
      {:ok, params, final, rest} ->
        seq = <<@esc, @csi>> <> params <> final
        take(rest, width, acc <> seq, sgr(final, params, attr))

      :incomplete ->
        finish(acc, attr)
    end
  end

  defp take(<<@esc, _byte, rest::binary>>, width, acc, attr) do
    take(rest, width, acc, attr)
  end

  defp take(<<@esc>>, _width, acc, attr), do: finish(acc, attr)

  defp take(bin, width, acc, attr) do
    case String.next_grapheme(bin) do
      {grapheme, rest} -> take(rest, width - 1, acc <> grapheme, attr)
      nil -> finish(acc, attr)
    end
  end

  defp csi(<<final, rest::binary>>, params) when final >= @final_min and final <= @final_max do
    {:ok, params, <<final>>, rest}
  end

  defp csi(<<byte, rest::binary>>, params) when byte >= 0x20 and byte <= 0x3F do
    csi(rest, params <> <<byte>>)
  end

  defp csi(<<>>, _params), do: :incomplete
  defp csi(_other, _params), do: :incomplete

  defp sgr("m", params, _attr) when params in ["", "0", "00", "22"], do: false
  defp sgr("m", _params, _attr), do: true
  defp sgr(_final, _params, attr), do: attr

  defp finish(acc, true), do: acc <> "\e[0m"
  defp finish(acc, false), do: acc
end
