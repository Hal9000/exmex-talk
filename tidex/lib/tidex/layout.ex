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

  defstruct [:width, :height, :status, :output, :footer_row]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          status: Pane.t(),
          output: Pane.t(),
          footer_row: pos_integer()
        }

  @status_height 6
  @footer_rows 1

  @spec compute(pos_integer(), pos_integer()) :: t()
  def compute(width, height) do
    width = max(width, 16)
    height = max(height, 12)
    output_height = height - @status_height - @footer_rows

    %__MODULE__{
      width: width,
      height: height,
      status: %Pane{row: 1, col: 1, width: width, height: @status_height},
      output: %Pane{row: @status_height + 1, col: 1, width: width, height: output_height},
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
end
