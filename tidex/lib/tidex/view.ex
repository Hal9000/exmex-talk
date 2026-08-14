defmodule Tidex.View do
  @moduledoc false

  alias Tidex.{Layout, Scroll, State}

  @spec render(Termex.Device.t(), State.t()) :: :ok
  def render(device, %State{} = state) do
    layout = Layout.compute(state.width, state.height, state.layout)

    Termex.clear_visible(device)
    Termex.move(device, 1, 1)

    render_status(device, state, layout.status)
    render_output(device, state, layout.output)
    render_footer(device, layout)
    render_overlay(device, state, layout)
    :ok
  end

  defp render_status(device, state, pane) do
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: "status")
    inner = Layout.inner(pane)
    lines = status_lines(state, inner.height)
    Termex.write_region(device, inner.row, inner.col, inner.width, inner.height, lines)
  end

  defp status_lines(state, height) when height >= 4 do
    [
      "project: #{state.project_name}",
      "tests:   #{state.test_state}",
      "server:  #{state.server_state}",
      git_line(state.git)
    ]
  end

  defp status_lines(state, _height) do
    [
      "tests: #{state.test_state}   server: #{state.server_state}",
      git_line(state.git)
    ]
  end

  defp git_line(%{branch: nil}), do: "git:     —"

  defp git_line(%{branch: branch, dirty: 0}), do: "git:     #{branch}"

  defp git_line(%{branch: branch, dirty: n}), do: "git:     #{branch} · #{n} dirty"

  defp render_output(device, state, pane) do
    inner = Layout.inner(pane)
    title = Scroll.title(state.output_lines, inner.height, state.output_scroll)
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: title)
    lines = Scroll.visible(state.output_lines, inner.height, state.output_scroll)
    Termex.write_region(device, inner.row, inner.col, inner.width, inner.height, lines)
  end

  defp render_footer(device, layout) do
    Termex.write_clipped(
      device,
      layout.footer_row - 1,
      1,
      layout.width,
      "[t]est [s]tart [x]stop [b]rowse"
    )

    Termex.write_clipped(
      device,
      layout.footer_row,
      1,
      layout.width,
      "[e]dit [l]ayout [?]help [q]uit"
    )
  end

  defp render_overlay(_device, %{overlay: nil}, _layout), do: :ok

  defp render_overlay(device, %{overlay: :help}, layout) do
    pane = overlay_pane(layout.width, layout.height)
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: "help")
    inner = Layout.inner(pane)
    fill_inner(device, inner)
    Termex.write_region(device, inner.row, inner.col, inner.width, inner.height, help_lines())
  end

  defp overlay_pane(width, height) do
    %Layout.Pane{
      row: 3,
      col: 3,
      width: max(width - 4, 12),
      height: max(min(height - 5, 14), 8)
    }
  end

  defp fill_inner(device, inner) do
    blank = String.duplicate(" ", max(inner.width, 0))

    Termex.write_region(
      device,
      inner.row,
      inner.col,
      inner.width,
      inner.height,
      List.duplicate(blank, max(inner.height, 0))
    )
  end

  defp help_lines do
    [
      "t  run tests",
      "s  start/restart server",
      "x  stop server",
      "b  open browser",
      "e  editor",
      "l  toggle layout",
      "arrows  scroll output",
      "?  this help",
      "q  quit",
      "",
      "esc or ? closes"
    ]
  end
end
