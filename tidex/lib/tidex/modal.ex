defmodule Tidex.Modal do
  @moduledoc false

  alias Tidex.{Layout, Scroll}
  alias Tidex.Layout.Pane

  defstruct title: nil,
            top_lines: [],
            lines: [],
            commands: "",
            kind: nil,
            page: nil,
            selection: 0,
            scroll: 0,
            max_width: 50,
            max_height: 10,
            min_width: 3,
            min_height: 3

  @type t :: %__MODULE__{
          title: String.t() | nil,
          top_lines: [iodata()],
          lines: [iodata()],
          commands: iodata(),
          kind: atom() | nil,
          page: term(),
          selection: non_neg_integer(),
          scroll: Scroll.t(),
          max_width: pos_integer(),
          max_height: pos_integer(),
          min_width: pos_integer(),
          min_height: pos_integer()
        }

  @spec pane(%{width: pos_integer(), height: pos_integer()}, t()) :: Pane.t()
  def pane(screen, %__MODULE__{} = modal) do
    width = outer_width(screen, modal)
    height = outer_height(screen, modal)

    %Pane{
      row: origin(screen.height, height),
      col: origin(screen.width, width),
      width: width,
      height: height
    }
  end

  @spec draw(Termex.Device.t(), %{width: pos_integer(), height: pos_integer()}, t()) :: :ok
  def draw(device, screen, %__MODULE__{} = modal) do
    pane = pane(screen, modal)
    inner = Layout.inner(pane)
    regions = regions(inner, modal)

    Termex.box(device, pane.row, pane.col, pane.width, pane.height,
      title: modal.title,
      frame_color: :bright_cyan,
      frame_style: :double
    )

    fill(device, inner)

    if regions.top_height > 0 do
      top_lines = Enum.take(modal.top_lines, regions.top_height)

      Termex.write_region(
        device,
        inner.row,
        inner.col,
        inner.width,
        regions.top_height,
        top_lines
      )
    end

    if regions.top_divider == 1 do
      Termex.box_divider(device, regions.body_row - 1, pane.col, pane.width,
        frame_color: :bright_cyan,
        frame_style: :double,
        divider_style: :light
      )
    end

    lines = Scroll.visible(modal.lines, regions.body_height, modal.scroll)

    Termex.write_region(
      device,
      regions.body_row,
      inner.col,
      inner.width,
      regions.body_height,
      lines
    )

    if regions.footer_height == 2 do
      Termex.box_divider(device, inner.row + inner.height - 2, pane.col, pane.width,
        frame_color: :bright_cyan,
        frame_style: :double,
        divider_style: :light
      )
    end

    if inner.height > 0 do
      commands = Termex.clip(modal.commands, inner.width)
      command_width = visible_width(commands)
      command_offset = div(max(inner.width - command_width, 0), 2)
      commands = Termex.color(commands, :bright_cyan)

      Termex.write_clipped(
        device,
        inner.row + inner.height - 1,
        inner.col + command_offset,
        inner.width - command_offset,
        commands
      )
    end

    :ok
  end

  @spec body_height(%{width: pos_integer(), height: pos_integer()}, t()) :: non_neg_integer()
  def body_height(screen, %__MODULE__{} = modal) do
    screen
    |> pane(modal)
    |> Layout.inner()
    |> regions(modal)
    |> Map.fetch!(:body_height)
  end

  defp fill(_device, %{width: w, height: h}) when w <= 0 or h <= 0, do: :ok

  defp fill(device, inner) do
    blank = String.duplicate(" ", inner.width)

    Termex.write_region(
      device,
      inner.row,
      inner.col,
      inner.width,
      inner.height,
      List.duplicate(blank, inner.height)
    )
  end

  defp outer_width(screen, modal) do
    inner =
      [modal.commands | modal.top_lines ++ modal.lines]
      |> Enum.map(&visible_width/1)
      |> Enum.max(fn -> 1 end)
      |> max(title_inner_width(modal.title))
      |> max(1)

    (inner + 2)
    |> max(modal.min_width)
    |> min(modal.max_width)
    |> min(screen.width)
    |> max(2)
  end

  defp outer_height(screen, modal) do
    top_divider = if modal.top_lines == [], do: 0, else: 1

    (length(modal.top_lines) + top_divider + length(modal.lines) + 1 + 1 + 2)
    |> max(modal.min_height)
    |> min(modal.max_height)
    |> min(screen.height)
    |> max(2)
  end

  defp title_inner_width(nil), do: 0
  defp title_inner_width(title), do: visible_width(title) + 3

  defp visible_width(text) do
    text
    |> IO.iodata_to_binary()
    |> Termex.ANSI.strip()
    |> String.length()
  end

  defp regions(inner, modal) do
    footer_height = min(inner.height, 2)
    available = max(inner.height - footer_height, 0)
    requested_top = length(modal.top_lines)
    top_height = min(requested_top, max(available - 2, 0))
    top_divider = if top_height > 0, do: 1, else: 0

    %{
      top_height: top_height,
      top_divider: top_divider,
      body_row: inner.row + top_height + top_divider,
      body_height: max(available - top_height - top_divider, 0),
      footer_height: footer_height
    }
  end

  defp origin(_screen, box) when box <= 1, do: 1
  defp origin(screen, box), do: max(div(screen - box, 2) + 1, 1)
end
