defmodule Tidex.LobbyLayout do
  @moduledoc false

  alias Tidex.Layout.Pane

  @lobby_max_width 80
  @inset 1
  @gap 1
  @pad 1
  @test_height 6
  @git_height 6
  @server_height 7
  @help_lines 2

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
  def content_rows(state) do
    @inset + max(left_span(state), right_span()) + @inset
  end

  @spec quadrants(Pane.t(), Tidex.State.t()) :: map()
  def quadrants(%Pane{} = pane, state) do
    inner_width = max(pane.width - 2 - 2 * @inset, 2)
    {left_w, right_w} = columns(inner_width)
    origin_row = pane.row + 1 + @inset
    origin_col = pane.col + 1 + @inset
    bottom_row = origin_row + @test_height + @gap

    server = %Pane{
      row: origin_row + @git_height + @gap,
      col: origin_col + left_w + @gap,
      width: right_w,
      height: @server_height
    }

    %{
      test: %Pane{row: origin_row, col: origin_col, width: left_w, height: @test_height},
      git: %Pane{
        row: origin_row,
        col: origin_col + left_w + @gap,
        width: right_w,
        height: @git_height
      },
      files: %Pane{
        row: bottom_row,
        col: origin_col,
        width: left_w,
        height: files_height(state)
      },
      server: server,
      help_row: server.row + server.height + @gap,
      help_col: server.col + 1 + @pad
    }
  end

  @spec content(Pane.t()) :: Pane.t()
  def content(%Pane{row: row, col: col, width: width, height: height}) do
    %Pane{
      row: row + 1 + @pad,
      col: col + 1 + @pad,
      width: max(width - 2 - 2 * @pad, 0),
      height: max(height - 2 - @pad, 0)
    }
  end

  defp columns(inner_width) do
    usable = max(inner_width - @gap, 2)
    left = div(usable, 2)
    {left, usable - left}
  end

  defp left_span(state), do: @test_height + @gap + files_height(state)

  defp right_span, do: @git_height + @gap + @server_height + @gap + @help_lines

  defp files_height(state) do
    2 + @pad + file_count(state)
  end

  defp file_count(state) do
    1 + Enum.count(1..4, &Map.has_key?(state.files, &1))
  end
end
