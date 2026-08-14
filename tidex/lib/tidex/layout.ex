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

  defstruct [:width, :height, :status, :fail, :output, :footer_row, :mode]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          status: Pane.t(),
          fail: Pane.t() | nil,
          output: Pane.t(),
          footer_row: pos_integer(),
          mode: Tidex.State.layout()
        }

  @footer_rows 2
  @fail_height 4
  @min_output_with_fail 4

  @spec compute(Tidex.State.t()) :: t()
  def compute(%Tidex.State{} = state) do
    compute(state.width, state.height, state.layout, failures: Tidex.Failures.showing?(state))
  end

  @spec compute(pos_integer(), pos_integer(), Tidex.State.layout(), keyword()) :: t()
  def compute(width, height, mode \\ :dashboard, opts \\ []) do
    width = max(width, 16)
    height = max(height, 12)
    status_height = status_height(mode)
    available = height - status_height - @footer_rows
    fail_height = fail_height(opts, available)
    output_height = available - fail_height

    fail =
      if fail_height > 0 do
        %Pane{row: status_height + 1, col: 1, width: width, height: fail_height}
      end

    %__MODULE__{
      width: width,
      height: height,
      mode: mode,
      status: %Pane{row: 1, col: 1, width: width, height: status_height},
      fail: fail,
      output: %Pane{
        row: status_height + fail_height + 1,
        col: 1,
        width: width,
        height: output_height
      },
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

  defp fail_height(opts, available) do
    if Keyword.get(opts, :failures, false) and available >= @fail_height + @min_output_with_fail do
      @fail_height
    else
      0
    end
  end
end
