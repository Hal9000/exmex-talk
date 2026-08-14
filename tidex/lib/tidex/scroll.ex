defmodule Tidex.Scroll do
  @moduledoc false

  @type t :: :follow | non_neg_integer()

  @spec visible([String.t()], integer(), t()) :: [String.t()]
  def visible(_lines, height, _scroll) when height <= 0, do: []

  def visible(lines, height, :follow) do
    Enum.take(lines, -height)
  end

  def visible(lines, height, offset) when is_integer(offset) do
    lines
    |> Enum.drop(clamp(offset, lines, height))
    |> Enum.take(height)
  end

  @spec step([String.t()], integer(), t(), integer()) :: t()
  def step(lines, height, scroll, delta) do
    height = max(height, 0)
    bottom = max_offset(lines, height)
    next = clamp(offset(lines, height, scroll) + delta, lines, height)

    if next >= bottom do
      :follow
    else
      next
    end
  end

  @spec title([String.t()], integer(), t()) :: String.t()
  def title(_lines, _height, :follow), do: "output"

  def title(lines, height, offset) do
    total = length(lines)
    height = max(height, 0)
    offset = clamp(offset, lines, height)

    if total == 0 or height == 0 or offset >= max_offset(lines, height) do
      "output"
    else
      from = offset + 1
      to = min(offset + height, total)
      "output #{from}-#{to}/#{total}"
    end
  end

  defp offset(lines, height, :follow), do: max_offset(lines, height)
  defp offset(_lines, _height, offset) when is_integer(offset), do: offset

  defp max_offset(lines, height), do: max(length(lines) - height, 0)

  defp clamp(offset, lines, height) do
    offset
    |> max(0)
    |> min(max_offset(lines, height))
  end
end
