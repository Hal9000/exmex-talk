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

  defstruct [:width, :height, :status, :fail, :output]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          status: Pane.t(),
          fail: Pane.t() | nil,
          output: Pane.t() | nil
        }

  @type sheet :: %{fail: Pane.t() | nil, log: Pane.t()}

  @menu_rows 1
  @fail_height 4
  @min_log_with_fail 4
  @lobby_max_width 80

  @spec compute(Tidex.State.t()) :: t()
  def compute(%Tidex.State{} = state) do
    compute(state.width, state.height)
  end

  @spec compute(pos_integer(), pos_integer()) :: t()
  def compute(width, height) do
    width = max(width, 16)
    height = max(height, 12)

    %__MODULE__{
      width: width,
      height: height,
      status: %Pane{row: 1, col: 1, width: width, height: height},
      fail: nil,
      output: nil
    }
  end

  @spec lobby(pos_integer(), pos_integer(), pos_integer()) :: Pane.t()
  def lobby(screen_width, screen_height, content_rows) do
    screen_width = max(screen_width, 16)
    screen_height = max(screen_height, 12)
    width = min(screen_width, @lobby_max_width)
    height = min(max(content_rows + 2, 3), screen_height)

    %Pane{
      row: div(screen_height - height, 2) + 1,
      col: div(screen_width - width, 2) + 1,
      width: width,
      height: height
    }
  end

  @spec sheet(Tidex.State.t()) :: sheet()
  def sheet(%Tidex.State{} = state) do
    width = max(state.width, 16)
    height = max(state.height, 12)
    available = height - @menu_rows
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
      height: height - @menu_rows
    }
  end

  @spec menu_row(pos_integer() | Tidex.State.t()) :: pos_integer()
  def menu_row(%{height: height}), do: menu_row(height)
  def menu_row(height) when is_integer(height), do: max(height, 12)

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
