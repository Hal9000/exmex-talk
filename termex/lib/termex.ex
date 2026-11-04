defmodule Termex do
  @moduledoc """
  A small terminal UI runtime.

  Termex grows only when an application needs a new capability. Tidex
  currently needs: clear, cursor, write, keys (including arrows), boxes,
  clipped text (CSI is width 0), text styles, and yielding the terminal
  to an external editor.
  """

  alias Termex.{ANSI, Box, Clip, Device, Keyboard, Keys, RawMode}

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

  @doc "Hide the terminal cursor on `device`."
  @spec hide_cursor(Device.t()) :: :ok
  def hide_cursor(device), do: write(device, ANSI.hide_cursor())

  @doc "Show the terminal cursor on `device`."
  @spec show_cursor(Device.t()) :: :ok
  def show_cursor(device), do: write(device, ANSI.show_cursor())

  @doc "Move the cursor, then write `text`."
  @spec write_at(Device.t(), pos_integer(), pos_integer(), iodata()) :: :ok
  def write_at(device, row, col, text) do
    move(device, row, col)
    write(device, text)
  end

  @doc """
  Truncate `text` to `width` visible graphemes so it cannot spill a pane.

  CSI sequences (including SGR) have width 0 and are not split. If a
  graphic rendition is still open after truncation, a reset is appended.
  Newlines become spaces. Width `0` yields an empty string.
  """
  @spec clip(iodata(), non_neg_integer()) :: String.t()
  def clip(text, width), do: Clip.visible(text, width)

  @doc "Wrap `text` in bold, then reset."
  @spec bold(iodata()) :: String.t()
  def bold(text), do: ANSI.wrap_bold(text)

  @doc """
  Wrap `text` in dim, then reset.

  Existing styled spans may be nested inside `text`. Returns plain text
  when `NO_COLOR` is present in the environment.
  """
  @spec dim(iodata()) :: String.t()
  def dim(text), do: ANSI.wrap_dim(text)

  @doc """
  Wrap `text` in a foreground `color`, then reset.

  Supported colors are `:black`, `:red`, `:green`, `:yellow`, `:blue`,
  `:magenta`, `:cyan`, and `:white`, plus their `:bright_*` variants.
  Returns plain text when `NO_COLOR` is present in the environment.
  """
  @spec color(iodata(), ANSI.color()) :: String.t()
  def color(text, color), do: ANSI.wrap_color(text, color)

  @doc """
  Wrap `text` in reverse video, then reset.

  Returns plain text when `NO_COLOR` is present in the environment.
  """
  @spec reverse(iodata()) :: String.t()
  def reverse(text), do: ANSI.wrap_reverse(text)

  @doc "Write `text` at `{row, col}`, truncated to `width` columns."
  @spec write_clipped(Device.t(), pos_integer(), pos_integer(), non_neg_integer(), iodata()) ::
          :ok
  def write_clipped(device, row, col, width, text) do
    write_at(device, row, col, clip(text, width))
  end

  @doc """
  Write `lines` into a rectangular region, clipping each line to `width`
  and dropping anything past `height`.
  """
  @spec write_region(
          Device.t(),
          pos_integer(),
          pos_integer(),
          non_neg_integer(),
          non_neg_integer(),
          [
            iodata()
          ]
        ) :: :ok
  def write_region(_device, _row, _col, _width, height, _lines) when height <= 0, do: :ok

  def write_region(device, row, col, width, height, lines) do
    lines
    |> Enum.take(height)
    |> Enum.with_index()
    |> Enum.each(fn {line, index} ->
      write_clipped(device, row + index, col, width, line)
    end)
  end

  @doc "Draw a horizontal line of `width` box-drawing characters."
  @spec hline(Device.t(), pos_integer(), pos_integer(), non_neg_integer()) :: :ok
  def hline(_device, _row, _col, width) when width <= 0, do: :ok

  def hline(device, row, col, width) do
    write_at(device, row, col, Box.horizontal(width))
  end

  @doc "Draw a vertical line of `height` box-drawing characters."
  @spec vline(Device.t(), pos_integer(), pos_integer(), non_neg_integer()) :: :ok
  def vline(_device, _row, _col, height) when height <= 0, do: :ok

  def vline(device, row, col, height) do
    Enum.each(0..(height - 1), fn offset ->
      write_at(device, row + offset, col, Box.vertical())
    end)
  end

  @doc "Write a single box-drawing corner."
  @spec corner(Device.t(), pos_integer(), pos_integer(), atom()) :: :ok
  def corner(device, row, col, kind) do
    write_at(device, row, col, Box.corner(kind))
  end

  @doc """
  Draw a rectangle. `opts` may include `:title`, which is clipped to the
  top edge, and `:frame_color`. Frame color honors `NO_COLOR`.
  """
  @spec box(Device.t(), pos_integer(), pos_integer(), pos_integer(), pos_integer(), keyword()) ::
          :ok
  def box(device, row, col, width, height, opts \\ []) when width >= 2 and height >= 2 do
    title = Keyword.get(opts, :title)
    frame_color = Keyword.get(opts, :frame_color)
    inner_width = width - 2
    inner_height = height - 2
    right_col = col + width - 1
    bottom_row = row + height - 1

    write_frame_at(device, row, col, Box.corner(:top_left), frame_color)
    write_frame_at(device, row, right_col, Box.corner(:top_right), frame_color)
    write_frame_at(device, bottom_row, col, Box.corner(:bottom_left), frame_color)
    write_frame_at(device, bottom_row, right_col, Box.corner(:bottom_right), frame_color)

    write_frame_at(device, row, col + 1, Box.titled_edge(inner_width, title), frame_color)
    write_frame_at(device, bottom_row, col + 1, Box.horizontal(inner_width), frame_color)

    if inner_height > 0 do
      Enum.each(0..(inner_height - 1), fn offset ->
        write_frame_at(device, row + 1 + offset, col, Box.vertical(), frame_color)
        write_frame_at(device, row + 1 + offset, right_col, Box.vertical(), frame_color)
      end)
    end

    :ok
  end

  @doc """
  Draw a horizontal divider across a box.

  The divider includes left/right junctions and may use `:frame_color`,
  matching `box/6`.
  """
  @spec box_divider(Device.t(), pos_integer(), pos_integer(), pos_integer(), keyword()) :: :ok
  def box_divider(device, row, col, width, opts \\ []) when width >= 2 do
    text = Box.junction(:left) <> Box.horizontal(width - 2) <> Box.junction(:right)

    text =
      case Keyword.get(opts, :frame_color) do
        nil -> text
        color -> ANSI.wrap_color(text, color)
      end

    write_at(device, row, col, text)
  end

  defp write_frame_at(device, row, col, text, nil), do: write_at(device, row, col, text)

  defp write_frame_at(device, row, col, text, color),
    do: write_at(device, row, col, ANSI.wrap_color(text, color))

  @doc """
  Read a key from `device`.

  Single bytes stay strings (`"q"`, `<<3>>`). Arrow and page keys are
  atoms (`:up`, `:page_down`). A lone ESC is `:esc`. Returns `:eof`
  when the input is exhausted.
  """
  @spec read_key(Device.t()) :: Keys.t()
  def read_key(%Device{input: input}), do: Keys.read(input)

  @spec enter(Device.t()) :: {:ok, RawMode.session()}
  defdelegate enter(device), to: RawMode

  @spec leave(RawMode.session()) :: :ok
  defdelegate leave(session), to: RawMode

  @doc """
  Run `fun` with single-key input enabled when `device` is a real TTY.

  No-op for injected devices and non-TTY stdin, so tests can drive the
  same loop with `StringIO`.
  """
  @spec with_raw_mode(Device.t(), (-> result) | (RawMode.session() -> result)) :: result
        when result: var
  defdelegate with_raw_mode(device, fun), to: RawMode

  @doc """
  Clear the screen, restore cooked mode, run `fun`, then return to raw mode.

  Tidex uses this to launch `$EDITOR` and redraw when it exits.
  """
  @spec yield(Device.t(), RawMode.session(), (-> result)) :: result when result: var
  def yield(device, session, fun) do
    show_cursor(device)
    clear_visible(device)
    move(device, 1, 1)
    RawMode.yield(session, fun)
  end

  @doc "Start a process that forwards keys to `opts[:notify]` (default `self()`)."
  @spec keyboard(Device.t(), keyword()) :: {:ok, pid()}
  def keyboard(device, opts \\ []) do
    Keyboard.start_link(device, opts)
  end
end
