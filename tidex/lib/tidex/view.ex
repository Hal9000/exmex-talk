defmodule Tidex.View do
  @moduledoc false

  alias Tidex.{Layout, State}

  @spec render(Termex.Device.t(), State.t()) :: :ok
  def render(device, %State{} = state) do
    layout = Layout.compute(state.width, state.height)

    Termex.clear_visible(device)
    Termex.move(device, 1, 1)

    render_status(device, state, layout.status)
    render_output(device, state, layout.output)
    render_footer(device, layout)
    :ok
  end

  defp render_status(device, state, pane) do
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: "status")
    inner = Layout.inner(pane)

    Termex.write_clipped(
      device,
      inner.row,
      inner.col,
      inner.width,
      "project: #{state.project_name}"
    )

    Termex.write_clipped(
      device,
      inner.row + 1,
      inner.col,
      inner.width,
      "tests:   #{state.test_state}"
    )

    Termex.write_clipped(
      device,
      inner.row + 2,
      inner.col,
      inner.width,
      "server:  #{state.server_state}"
    )
  end

  defp render_output(device, state, pane) do
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: "output")
    inner = Layout.inner(pane)
    lines = Enum.take(state.output_lines, -inner.height)
    Termex.write_region(device, inner.row, inner.col, inner.width, inner.height, lines)
  end

  defp render_footer(device, layout) do
    Termex.write_clipped(
      device,
      layout.footer_row,
      1,
      layout.width,
      "[t] test   [s] server   [q] quit"
    )
  end
end
