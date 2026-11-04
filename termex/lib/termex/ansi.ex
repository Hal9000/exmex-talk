defmodule Termex.ANSI do
  @moduledoc """
  Pure ANSI escape sequences.

  These functions return strings. They do not write to a terminal, which
  keeps them easy to test and leaves IO in `Termex`.
  """

  @esc "\e"
  @foregrounds %{
    black: 30,
    red: 31,
    green: 32,
    yellow: 33,
    blue: 34,
    magenta: 35,
    cyan: 36,
    white: 37
  }

  @type color :: :black | :red | :green | :yellow | :blue | :magenta | :cyan | :white

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

  @spec foreground(color()) :: String.t()
  def foreground(color), do: @esc <> "[#{Map.fetch!(@foregrounds, color)}m"

  @spec reverse() :: String.t()
  def reverse, do: @esc <> "[7m"

  @spec reset() :: String.t()
  def reset, do: @esc <> "[0m"

  @doc "Wrap `text` in bold SGR, then reset."
  @spec wrap_bold(iodata()) :: String.t()
  def wrap_bold(text) do
    bold() <> IO.iodata_to_binary(text) <> reset()
  end

  @doc """
  Wrap `text` in a foreground color, unless `NO_COLOR` is present.
  """
  @spec wrap_color(iodata(), color(), map()) :: String.t()
  def wrap_color(text, color, env \\ System.get_env()) do
    wrap_if_enabled(text, foreground(color), env)
  end

  @doc """
  Wrap `text` in reverse video, unless `NO_COLOR` is present.
  """
  @spec wrap_reverse(iodata(), map()) :: String.t()
  def wrap_reverse(text, env \\ System.get_env()) do
    wrap_if_enabled(text, reverse(), env)
  end

  @doc "Whether visual styling controlled by `NO_COLOR` is enabled."
  @spec color_enabled?(map()) :: boolean()
  def color_enabled?(env \\ System.get_env()), do: not Map.has_key?(env, "NO_COLOR")

  @doc "Drop CSI sequences so tests can assert on visible text."
  @spec strip(iodata()) :: String.t()
  def strip(text) do
    text
    |> IO.iodata_to_binary()
    |> then(&Regex.replace(~r/\e\[[0-9;?]*[@-~]/, &1, ""))
    |> String.replace(~r/\e./, "")
  end

  defp wrap_if_enabled(text, sequence, env) do
    text = IO.iodata_to_binary(text)
    if color_enabled?(env), do: sequence <> text <> reset(), else: text
  end
end
