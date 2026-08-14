defmodule Termex.ANSI do
  @moduledoc """
  Pure ANSI escape sequences.

  These functions return strings. They do not write to a terminal, which
  keeps them easy to test and leaves IO in `Termex`.
  """

  @esc "\e"

  @doc """
  Erase the visible screen (CSI `2J`).

  This does not clear the terminal's scrollback buffer (CSI `3J`).
  """
  @spec clear_visible() :: String.t()
  def clear_visible, do: @esc <> "[2J"

  @doc """
  Move the cursor to a 1-based `{row, col}` position (CSI `H`).
  """
  @spec cursor(pos_integer(), pos_integer()) :: String.t()
  def cursor(row, col) when row >= 1 and col >= 1 do
    @esc <> "[#{row};#{col}H"
  end

  @spec show_cursor() :: String.t()
  def show_cursor, do: @esc <> "[?25h"

  @spec hide_cursor() :: String.t()
  def hide_cursor, do: @esc <> "[?25l"

  @spec bold() :: String.t()
  def bold, do: @esc <> "[1m"

  @spec reset() :: String.t()
  def reset, do: @esc <> "[0m"

  @doc "Wrap `text` in bold SGR, then reset."
  @spec wrap_bold(iodata()) :: String.t()
  def wrap_bold(text) do
    bold() <> IO.iodata_to_binary(text) <> reset()
  end

  @doc "Drop CSI sequences so tests can assert on visible text."
  @spec strip(iodata()) :: String.t()
  def strip(text) do
    text
    |> IO.iodata_to_binary()
    |> then(&Regex.replace(~r/\e\[[0-9;?]*[@-~]/, &1, ""))
    |> String.replace(~r/\e./, "")
  end
end
