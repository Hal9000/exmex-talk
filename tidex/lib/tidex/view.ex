defmodule Tidex.View do
  @moduledoc false

  alias Tidex.{Layout, Modal, Setup, State}

  @spec render(Termex.Device.t(), State.t()) :: :ok
  def render(device, %State{} = state) do
    Termex.hide_cursor(device)
    Termex.clear_visible(device)
    Termex.move(device, 1, 1)

    cond do
      state.overlay == :setup ->
        render_dimmed_status(device, state)
        Modal.draw(device, state, Setup.modal(state.setup))

      state.modal ->
        render_dimmed_status(device, state)
        Modal.draw(device, state, state.modal)

      true ->
        render_status(device, state)
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
    rows = status_line_count(state)
    pane = Layout.lobby(state.width, state.height, rows)
    inner = Layout.inner(pane)
    lines = status_lines(state, inner)
    title = "#{state.title} · #{state.project_name}"

    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: title)
    Termex.write_region(device, inner.row, inner.col, inner.width, inner.height, lines)
  end

  defp status_lines(state, inner) do
    col = max(div(inner.width, 2), 8)

    zip_pad(test_lines(state), server_lines(state), col) ++
      [""] ++
      zip_pad(git_lines(state.git), file_lines(state.files), col) ++
      ["", pad(key("?", "help"), col) <> key("q", "quit")]
  end

  defp status_line_count(state) do
    max(length(test_lines(state)), length(server_lines(state))) +
      1 +
      max(length(git_lines(state.git)), length(file_lines(state.files))) +
      2
  end

  defp zip_pad(left, right, col) do
    0..(max(length(left), length(right)) - 1)
    |> Enum.map(fn i ->
      pad(Enum.at(left, i) || "", col) <> (Enum.at(right, i) || "")
    end)
  end

  defp pad(text, width) do
    visible = String.length(Termex.ANSI.strip(text))
    text <> String.duplicate(" ", max(width - visible, 0))
  end

  defp test_lines(state) do
    [
      section_heading("Test", test_status(state)),
      key("t", "run tests"),
      key("f", "view failures")
    ]
  end

  defp test_status(%{test_state: :idle}), do: "idle"

  defp test_status(%{test_state: :running, failures: []}), do: "running"

  defp test_status(%{test_state: :running, failures: failures}),
    do: "running · #{length(failures)} fail"

  defp test_status(%{test_state: :pass}), do: "pass"

  defp test_status(%{test_state: :fail, failures: []}), do: "fail"

  defp test_status(%{test_state: :fail, failures: failures}),
    do: "fail · #{length(failures)} fail"

  defp server_lines(%{server_command: command})
       when not is_binary(command) or command == "" do
    ["Server", Termex.reverse("not configured")]
  end

  defp server_lines(state) do
    lines = [
      section_heading("Server", server_status(state.server_state)),
      key("s", server_action(state.server_state)),
      key("x", "stop")
    ]

    if is_binary(state.browser_url) and state.browser_url != "" do
      lines ++ [key("b", "open browser")]
    else
      lines
    end
  end

  defp server_action(status) when status in [:starting, :up, :stop_failed], do: "restart"
  defp server_action(_status), do: "start"

  defp server_status(:start_failed), do: "start failed"
  defp server_status(:stop_failed), do: "stop failed"
  defp server_status(:port_busy), do: "port busy"
  defp server_status(status), do: to_string(status)

  defp git_lines(%{branch: nil}) do
    [section_heading("Git", "no repository"), key("g", "open git")]
  end

  defp git_lines(git) do
    status =
      [git.branch]
      |> append_count(Map.get(git, :dirty, 0), "dirty")
      |> append_count(Map.get(git, :untracked, 0), "untracked")
      |> Enum.join(" · ")

    [section_heading("Git", status), key("g", "open git")]
  end

  defp append_count(lines, n, _label) when n in [0, nil], do: lines
  defp append_count(lines, n, label), do: lines ++ ["#{n} #{label}"]

  defp file_lines(files) do
    rows =
      1..4
      |> Enum.filter(&Map.has_key?(files, &1))
      |> Enum.map(fn n -> key("#{n}", files[n]) end)

    ["Files", key("0", "tidex.conf") | rows]
  end

  defp key(letter, rest), do: Termex.bold(letter) <> "  " <> rest

  defp section_heading(title, status), do: title <> " " <> Termex.reverse(status)
end
