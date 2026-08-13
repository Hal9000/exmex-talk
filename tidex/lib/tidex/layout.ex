defmodule Tidex.Layout do
  @moduledoc false

  defmodule Pane do
    @moduledoc false
    defstruct row: 1, col: 1, width: 80, height: 6

    @type t :: %__MODULE__{
            row: pos_integer(),
            col: pos_integer(),
            width: non_neg_integer(),
            height: non_neg_integer()
          }
  end

  defstruct [:width, :height, :status, :output, :footer_row, :mode]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          status: Pane.t(),
          output: Pane.t(),
          footer_row: pos_integer(),
          mode: Tidex.State.layout()
        }

  @footer_rows 1

  @spec compute(pos_integer(), pos_integer(), Tidex.State.layout()) :: t()
  def compute(width, height, mode \\ :dashboard) do
    width = max(width, 16)
    height = max(height, 12)
    status_height = status_height(mode)
    output_height = height - status_height - @footer_rows

    %__MODULE__{
      width: width,
      height: height,
      mode: mode,
      status: %Pane{row: 1, col: 1, width: width, height: status_height},
      output: %Pane{row: status_height + 1, col: 1, width: width, height: output_height},
      footer_row: height
    }
  end

  @spec inner(Pane.t()) :: Pane.t()
  def inner(%Pane{} = pane) do
    %Pane{
      row: pane.row + 1,
      col: pane.col + 1,
      width: max(pane.width - 2, 0),
      height: max(pane.height - 2, 0)
    }
  end

  defp status_height(:dashboard), do: 6
  defp status_height(:output), do: 4
end
