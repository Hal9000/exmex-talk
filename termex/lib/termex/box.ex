defmodule Termex.Box do
  @moduledoc """
  Box-drawing characters and border strings.

  These are data. `Termex` writes them to a device.
  """

  @type style :: :light | :double

  @spec horizontal() :: String.t()
  def horizontal, do: horizontal(:light)

  @spec horizontal(style()) :: String.t()
  def horizontal(:light), do: "─"
  def horizontal(:double), do: "═"

  @spec horizontal(non_neg_integer()) :: String.t()
  def horizontal(width) when is_integer(width) and width >= 0, do: horizontal(width, :light)

  @spec horizontal(non_neg_integer(), style()) :: String.t()
  def horizontal(width, style) when width >= 0,
    do: String.duplicate(horizontal(style), width)

  @spec vertical() :: String.t()
  def vertical, do: vertical(:light)

  @spec vertical(style()) :: String.t()
  def vertical(:light), do: "│"
  def vertical(:double), do: "║"

  @spec corner(:top_left | :top_right | :bottom_left | :bottom_right) :: String.t()
  def corner(kind), do: corner(kind, :light)

  @spec corner(:top_left | :top_right | :bottom_left | :bottom_right, style()) :: String.t()
  def corner(:top_left, :light), do: "┌"
  def corner(:top_right, :light), do: "┐"
  def corner(:bottom_left, :light), do: "└"
  def corner(:bottom_right, :light), do: "┘"
  def corner(:top_left, :double), do: "╔"
  def corner(:top_right, :double), do: "╗"
  def corner(:bottom_left, :double), do: "╚"
  def corner(:bottom_right, :double), do: "╝"

  @spec junction(:left | :right) :: String.t()
  def junction(side), do: junction(side, :light, :light)

  @spec junction(:left | :right, style(), style()) :: String.t()
  def junction(:left, :light, :light), do: "├"
  def junction(:right, :light, :light), do: "┤"
  def junction(:left, :double, :double), do: "╠"
  def junction(:right, :double, :double), do: "╣"
  def junction(:left, :double, :light), do: "╟"
  def junction(:right, :double, :light), do: "╢"
  def junction(:left, :light, :double), do: "╞"
  def junction(:right, :light, :double), do: "╡"

  @doc """
  Top border inner segment, optionally with a clipped title.

  With a title the segment looks like `─ status ────`.
  """
  @spec titled_edge(non_neg_integer(), String.t() | nil) :: String.t()
  def titled_edge(width, title), do: titled_edge(width, title, :light)

  @spec titled_edge(non_neg_integer(), String.t() | nil, style()) :: String.t()
  def titled_edge(width, nil, style), do: horizontal(width, style)
  def titled_edge(width, _title, _style) when width <= 0, do: ""

  def titled_edge(width, title, style) do
    clipped = Termex.clip(title, max(width - 3, 0))
    label = horizontal(style) <> " " <> clipped <> " "
    pad = width - visible_width(label)

    if pad < 0 do
      Termex.clip(label, width)
    else
      label <> horizontal(pad, style)
    end
  end

  defp visible_width(text) do
    text
    |> Termex.ANSI.strip()
    |> String.length()
  end
end
