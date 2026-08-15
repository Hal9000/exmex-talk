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

  defstruct [:width, :height, :status, :fail, :output, :footer_row]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          status: Pane.t(),
          fail: Pane.t() | nil,
          output: Pane.t() | nil,
          footer_row: pos_integer()
        }

  @type sheet :: %{fail: Pane.t() | nil, log: Pane.t()}

  @footer_rows 2
  @fail_height 4
  @min_log_with_fail 4
  @lobby_status_height 18

  @spec compute(Tidex.State.t()) :: t()
  def compute(%Tidex.State{} = state) do
    compute(state.width, state.height)
  end

  @spec compute(pos_integer(), pos_integer()) :: t()
  def compute(width, height) do
    width = max(width, 16)
    height = max(height, 12)
    available = height - @footer_rows
    status_height = min(@lobby_status_height, available)

    %__MODULE__{
      width: width,
      height: height,
      status: %Pane{row: 1, col: 1, width: width, height: status_height},
      fail: nil,
      output: nil,
      footer_row: height
    }
  end

  @spec sheet(Tidex.State.t()) :: sheet()
  def sheet(%Tidex.State{} = state) do
    width = max(state.width, 16)
    height = max(state.height, 12)
    available = height - @footer_rows
    fail_height = sheet_fail_height(state, available)

    fail =
      if fail_height > 0 do
        %Pane{row: 1, col: 1, width: width, height: fail_height}
      end

    %{
      fail: fail,
      log: %Pane{
        row: 1 + fail_height,
        col: 1,
        width: width,
        height: available - fail_height
      }
    }
  end

  @spec overlay_pane(pos_integer(), pos_integer()) :: Pane.t()
  def overlay_pane(width, height) do
    width = max(width, 16)
    height = max(height, 12)

    %Pane{
      row: 1,
      col: 1,
      width: width,
      height: height - @footer_rows
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

  defp sheet_fail_height(%{overlay: :test} = state, available) do
    if Tidex.Failures.showing?(state) and available >= @fail_height + @min_log_with_fail do
      @fail_height
    else
      0
    end
  end

  defp sheet_fail_height(_state, _available), do: 0
end
