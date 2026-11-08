defmodule Tidex.LobbyLayout do
  @moduledoc false

  alias Tidex.Layout.Pane

  @lobby_max_width 80
  @column_gap 0
  @top_height 5
  @files_height 7
  @git_height 4
  @footer_lines 1

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

  @spec content_rows(Tidex.State.t()) :: pos_integer()
  def content_rows(_state) do
    @top_height + max(@files_height, @git_height) + @footer_lines
  end

  @spec columns(non_neg_integer()) :: {pos_integer(), pos_integer()}
  def columns(inner_width) do
    usable = max(inner_width - @column_gap, 2)
    left = div(usable, 2)
    right = usable - left
    {left, right}
  end

  @spec quadrants(Pane.t()) :: %{
          test: Pane.t(),
          server: Pane.t(),
          files: Pane.t(),
          git: Pane.t(),
          footer_row: pos_integer()
        }
  def quadrants(%Pane{row: base_row, col: base_col, width: width, height: _height}) do
    inner_width = max(width - 2, 0)
    {left_w, right_w} = columns(inner_width)
    inner_row = base_row + 1
    inner_col = base_col + 1

    top_row = inner_row
    bottom_row = inner_row + @top_height
    footer_row = bottom_row + max(@files_height, @git_height)

    %{
      test: %Pane{row: top_row, col: inner_col, width: left_w, height: @top_height},
      server: %Pane{row: top_row, col: inner_col + left_w + @column_gap, width: right_w, height: @top_height},
      files: %Pane{row: bottom_row, col: inner_col, width: left_w, height: @files_height},
      git: %Pane{row: bottom_row, col: inner_col + left_w + @column_gap, width: right_w, height: @git_height},
      footer_row: footer_row
    }
  end

  @spec inner(Pane.t()) :: Pane.t()
  def inner(%Pane{row: row, col: col, width: width, height: height}) do
    %Pane{
      row: row + 1,
      col: col + 1,
      width: max(width - 2, 0),
      height: max(height - 2, 0)
    }
  end
end
