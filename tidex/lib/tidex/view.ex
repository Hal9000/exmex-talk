defmodule Tidex.View do
  @moduledoc false

  alias Tidex.{Layout, State}

  @spec render(Termex.Device.t(), State.t()) :: :ok
  def render(device, %State{} = state) do
    layout = Layout.compute(state.width, state.height, state.layout)

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
      "[t]est [s]tart [x]stop [b]rowse [e]dit [l]ayout [q]uit"
    )
  end
end
