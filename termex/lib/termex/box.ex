defmodule Termex.Box do
  @moduledoc """
  Box-drawing characters and border strings.

  These are data. `Termex` writes them to a device.
  """

  @horizontal "─"
  @vertical "│"

  @spec horizontal() :: String.t()
  def horizontal, do: @horizontal

  @spec vertical() :: String.t()
  def vertical, do: @vertical

  @spec horizontal(non_neg_integer()) :: String.t()
  def horizontal(width) when width >= 0, do: String.duplicate(@horizontal, width)

  @spec corner(:top_left | :top_right | :bottom_left | :bottom_right) :: String.t()
  def corner(:top_left), do: "┌"
  def corner(:top_right), do: "┐"
  def corner(:bottom_left), do: "└"
  def corner(:bottom_right), do: "┘"

  @spec junction(:left | :right) :: String.t()
  def junction(:left), do: "├"
  def junction(:right), do: "┤"

  @doc """
  Top border inner segment, optionally with a clipped title.

  With a title the segment looks like `─ status ────`.
  """
  @spec titled_edge(non_neg_integer(), String.t() | nil) :: String.t()
  def titled_edge(width, nil), do: horizontal(width)
  def titled_edge(width, _title) when width <= 0, do: ""

  def titled_edge(width, title) do
    clipped = Termex.clip(title, max(width - 3, 0))
    label = "─ " <> clipped <> " "
    pad = width - String.length(label)

    if pad < 0 do
      Termex.clip(label, width)
    else
      label <> horizontal(pad)
    end
  end
end
