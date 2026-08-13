defmodule Termex do
  @moduledoc """
  A small terminal UI runtime.

  Termex grows only when an application needs a new capability. This first
  slice can clear the visible screen, move the cursor, write text, and read
  a single key — enough for Tidex to draw a dashboard and react to keys.
  """

  alias Termex.{ANSI, Device, RawMode}

  @doc "Clear the visible screen on `device`."
  @spec clear_visible(Device.t()) :: :ok
  def clear_visible(%Device{output: output}) do
    IO.write(output, ANSI.clear_visible())
  end

  @doc "Move the cursor to a 1-based `{row, col}` on `device`."
  @spec move(Device.t(), pos_integer(), pos_integer()) :: :ok
  def move(%Device{output: output}, row, col) do
    IO.write(output, ANSI.cursor(row, col))
  end

  @doc "Write `text` at the current cursor position."
  @spec write(Device.t(), iodata()) :: :ok
  def write(%Device{output: output}, text) do
    IO.write(output, text)
  end

  @doc "Move the cursor, then write `text`. Tidex needed this immediately."
  @spec write_at(Device.t(), pos_integer(), pos_integer(), iodata()) :: :ok
  def write_at(device, row, col, text) do
    move(device, row, col)
    write(device, text)
  end

  @doc """
  Read a single byte/key from `device`.

  Returns `:eof` when the input is exhausted.
  """
  @spec read_key(Device.t()) :: String.t() | :eof
  def read_key(%Device{input: input}) do
    case IO.getn(input, "", 1) do
      :eof -> :eof
      {:error, _} -> :eof
      key when is_binary(key) and byte_size(key) > 0 -> key
      [char] when is_integer(char) -> <<char>>
      _ -> :eof
    end
  end

  @doc """
  Run `fun` with single-key input enabled when `device` is a real TTY.

  No-op for injected devices and non-TTY stdin, so tests can drive the
  same loop with `StringIO`.
  """
  @spec with_raw_mode(Device.t(), (-> result)) :: result when result: var
  defdelegate with_raw_mode(device, fun), to: RawMode
end
