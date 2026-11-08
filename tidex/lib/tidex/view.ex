defmodule Tidex.View do
  @moduledoc false

  alias Tidex.{Layout, LobbyLayout, Modal, Setup, State}

  @spec render(Termex.Device.t(), State.t()) :: :ok
  def render(device, %State{} = state) do
    Termex.hide_cursor(device)
    Termex.clear_visible(device)
    Termex.move(device, 1, 1)

    if state.overlay == nil do
      if state.modal do
        render_dimmed_status(device, state)
        Modal.draw(device, state, state.modal)
      else
        render_status(device, state)
      end
    else
      render_sheet(device, state)
      render_menu(device, state)
    end

    :ok
  end

  defp render_dimmed_status(device, state) do
    {:ok, output} = StringIO.open("")
    render_status(%{device | output: output}, state)
    {_input, text} = StringIO.contents(output)
    StringIO.close(output)
    Termex.write(device, Termex.dim(text))
  end

  defp render_status(device, state) do
    rows = LobbyLayout.content_rows(state)
    pane = LobbyLayout.lobby(state.width, state.height, rows)
    q = LobbyLayout.quadrants(pane, state)
    title = "#{state.title} · #{state.project_name}"

    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: title)

    draw_test_quadrant(device, q.test, state)
    draw_server_quadrant(device, q.server, state)
    draw_files_quadrant(device, q.files, state)
    draw_git_quadrant(device, q.git, state.git)
    draw_help(device, q.help_row, q.help_col)
  end

  defp draw_test_quadrant(device, pane, state) do
    box_title = titled("Test", test_title_status(state))

    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: box_title)
    body = LobbyLayout.content(pane)

    Termex.write_clipped(device, body.row, body.col, body.width, key("t", "Run tests"))
    Termex.write_clipped(device, body.row + 1, body.col, body.width, key("f", "Step through failures"))

    write_status_line(
      device,
      pane.row + pane.height - 2,
      body.col,
      body.width,
      test_long_status(state)
    )
  end

  defp draw_server_quadrant(device, pane, state) do
    status = server_title_status(state)
    box_title = titled("Server", status)

    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: box_title)
    body = LobbyLayout.content(pane)

    lines =
      if server_configured?(state) do
        [
          key("s", "Start/restart"),
          key("x", "Stop")
          | if(browser?(state), do: [key("b", "Browse to server")], else: [])
        ]
      else
        [key("s", "Start/restart"), key("x", "Stop")]
      end

    Termex.write_region(device, body.row, body.col, body.width, length(lines), lines)
  end

  defp draw_files_quadrant(device, pane, state) do
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: "Edit files")
    body = LobbyLayout.content(pane)

    lines =
      [key("0", "tidex.conf")] ++
        (1..4
         |> Enum.filter(&Map.has_key?(state.files, &1))
         |> Enum.map(fn n -> key("#{n}", state.files[n]) end))

    Termex.write_region(device, body.row, body.col, body.width, length(lines), lines)
  end

  defp draw_git_quadrant(device, pane, git) do
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: git_box_title(git))
    body = LobbyLayout.content(pane)

    Termex.write_clipped(device, body.row, body.col, body.width, key("i", "More information"))
    Termex.write_clipped(device, body.row + 1, body.col, body.width, key("g", "Open full pane"))
  end

  defp draw_help(device, row, col) do
    Termex.write_clipped(device, row, col, 16, key("?", "help"))
    Termex.write_clipped(device, row + 1, col, 16, key("q", "quit"))
  end

  defp titled(label, status) when status in [nil, ""] do
    label
  end

  defp titled(label, status) do
    label <> " ─ " <> Termex.reverse(Termex.clip(status, 24))
  end

  defp test_title_status(%{test_state: :running}), do: "Running"
  defp test_title_status(%{test_state: :fail}), do: "Fail"
  defp test_title_status(_), do: ""

  defp test_long_status(%{test_state: :idle}), do: ""

  defp test_long_status(%{test_state: :running, failures: failures}) do
    case length(failures) do
      0 -> ""
      n -> "#{n} fail"
    end
  end

  defp test_long_status(%{test_state: :pass}), do: "pass"

  defp test_long_status(%{test_state: :fail, failures: []}), do: "fail"

  defp test_long_status(%{test_state: :fail, failures: failures}) do
    "#{length(failures)} fail"
  end

  defp server_title_status(%{server_command: command})
       when not is_binary(command) or command == "" do
    "not configured"
  end

  defp server_title_status(%{server_state: status}), do: server_status_label(status)

  defp server_status_label(:start_failed), do: "start failed"
  defp server_status_label(:stop_failed), do: "stop failed"
  defp server_status_label(:port_busy), do: "port busy"
  defp server_status_label(status), do: to_string(status)

  defp git_box_title(%{branch: nil}), do: "git"

  defp git_box_title(git) do
    dirty = Map.get(git, :dirty, 0)
    untracked = Map.get(git, :untracked, 0)

    if dirty > 0 or untracked > 0, do: titled("git", "dirty"), else: "git"
  end

  defp write_status_line(device, row, col, width, "") do
    Termex.write_clipped(device, row, col, width, String.duplicate(" ", width))
  end

  defp write_status_line(device, row, col, width, text) do
    visible = String.length(text)
    pad = max(width - visible, 0)
    line = Termex.reverse(text <> String.duplicate(" ", pad))
    Termex.write_clipped(device, row, col, width, line)
  end

  defp server_configured?(state),
    do: is_binary(state.server_command) and state.server_command != ""

  defp browser?(state), do: is_binary(state.browser_url) and state.browser_url != ""

  defp render_menu(device, state) do
    Termex.write_clipped(
      device,
      Layout.menu_row(state),
      1,
      state.width,
      menu_line(state.overlay)
    )
  end

  defp menu_line(:setup), do: "esc skip"

  defp menu_line(_), do: "esc back"

  defp render_sheet(device, %{overlay: :setup} = state) do
    draw_overlay(device, state, "tidex.conf", Setup.lines(state.setup))
  end

  defp draw_overlay(device, state, title, lines) do
    pane = Layout.overlay_pane(state.width, state.height)
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: title)
    inner = Layout.inner(pane)
    fill_inner(device, inner)
    Termex.write_region(device, inner.row, inner.col, inner.width, inner.height, lines)
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

  defp key(letter, rest), do: Termex.bold(letter) <> "  " <> rest
end
