defmodule Tidex.Modal do
  @moduledoc false

  alias Tidex.Layout
  alias Tidex.Layout.Pane

  defstruct title: nil,
            lines: [],
            commands: "",
            kind: nil,
            max_width: 50,
            max_height: 10,
            min_width: 3,
            min_height: 3

  @type t :: %__MODULE__{
          title: String.t() | nil,
          lines: [iodata()],
          commands: iodata(),
          kind: atom() | nil,
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
    body_height = max(inner.height - 1, 0)

    Termex.box(device, pane.row, pane.col, pane.width, pane.height,
      title: modal.title,
      frame_color: :bright_cyan
    )

    fill(device, inner)
    Termex.write_region(device, inner.row, inner.col, inner.width, body_height, modal.lines)

    if inner.height > 0 do
      Termex.write_clipped(
        device,
        inner.row + inner.height - 1,
        inner.col,
        inner.width,
        modal.commands
      )
    end

    :ok
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
      [modal.commands | modal.lines]
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
    (length(modal.lines) + 1 + 2)
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

  defp origin(_screen, box) when box <= 1, do: 1
  defp origin(screen, box), do: max(div(screen - box, 2) + 1, 1)
end
