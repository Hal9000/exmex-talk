defmodule Tidex.View do
  @moduledoc false

  alias Tidex.{Layout, Scroll, Setup, State}

  @spec render(Termex.Device.t(), State.t()) :: :ok
  def render(device, %State{} = state) do
    layout = Layout.compute(state)

    Termex.clear_visible(device)
    Termex.move(device, 1, 1)

    if state.overlay == nil do
      render_status(device, state, layout.status)
    else
      render_sheet(device, state)
      render_menu(device, state)
    end

    :ok
  end

  defp render_status(device, state, pane) do
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: "status")
    inner = Layout.inner(pane)
    lines = status_lines(state, inner)
    Termex.write_region(device, inner.row, inner.col, inner.width, inner.height, lines)
  end

  defp status_lines(state, inner) do
    col = max(div(inner.width, 2), 8)

    [
      "project: #{state.project_name}",
      ""
    ] ++
      zip_pad(test_lines(state), server_lines(state), col) ++
      [""] ++
      zip_pad(git_lines(state.git), file_lines(state.files), col) ++
      ["", pad(key("?", "help"), col) <> key("q", "quit")]
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
    ["Test", test_status_line(state), key("e", "edit")]
  end

  defp test_status_line(%{test_state: :idle}), do: key("t", "idle")

  defp test_status_line(%{test_state: :fail, failures: []}), do: key("t", "fail")

  defp test_status_line(state) do
    key("t", "- pass  #{length(state.failures)} fail")
  end

  defp server_lines(state) do
    ["Server", key("s", "#{state.server_state}"), key("x", "stop"), key("b", "browse")]
  end

  defp git_lines(%{branch: nil}) do
    ["Git", key("g", "(no repository)")]
  end

  defp git_lines(git) do
    ["Git", key("g", git.branch)]
    |> append_count(Map.get(git, :dirty, 0), "dirty")
    |> append_count(Map.get(git, :untracked, 0), "untracked")
  end

  defp append_count(lines, n, _label) when n in [0, nil], do: lines
  defp append_count(lines, n, label), do: lines ++ ["   #{n} #{label}"]

  defp file_lines(files) do
    rows =
      1..4
      |> Enum.filter(&Map.has_key?(files, &1))
      |> Enum.map(fn n -> key("#{n}", files[n]) end)

    ["Files", key("f", "tidex.conf") | rows]
  end

  defp render_log(device, state, pane, name) do
    inner = Layout.inner(pane)
    title = log_title(state.output_lines, inner.height, state.output_scroll, name)
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: title)
    lines = Scroll.visible(state.output_lines, inner.height, state.output_scroll)
    Termex.write_region(device, inner.row, inner.col, inner.width, inner.height, lines)
  end

  defp log_title(lines, height, scroll, name) do
    case Scroll.title(lines, height, scroll) do
      "output" -> name
      "output " <> rest -> "#{name} #{rest}"
    end
  end

  defp render_menu(device, state) do
    Termex.write_clipped(
      device,
      Layout.menu_row(state),
      1,
      state.width,
      menu_line(state.overlay)
    )
  end

  defp menu_line(:server) do
    Enum.join(
      [hotkey("s", "start"), hotkey("x", "stop"), hotkey("b", "browse"), "esc back"],
      "  "
    )
  end

  defp menu_line(:git) do
    Enum.join(
      [hotkey("a", "add") <> " -u", hotkey("c", "commit"), hotkey("p", "push"), "esc back"],
      "  "
    )
  end

  defp menu_line(:help), do: "esc back"

  defp menu_line(:setup), do: "esc skip"

  defp menu_line(_), do: "esc back"

  defp render_sheet(device, %{overlay: :server} = state) do
    sheet = Layout.sheet(state)
    render_log(device, state, sheet.log, "server · #{state.server_state}")
  end

  defp render_sheet(device, %{overlay: :setup} = state) do
    draw_overlay(device, state, "tidex.conf", Setup.lines(state.setup))
  end

  defp render_sheet(device, %{overlay: :help} = state) do
    draw_overlay(device, state, "help", help_lines())
  end

  defp render_sheet(device, %{overlay: :git} = state) do
    draw_overlay(device, state, "git", git_sheet_lines(state))
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

  defp help_lines do
    [
      key("t", "run tests"),
      key("s", "server sheet (again to start)"),
      key("x", "stop server"),
      key("b", "open browser"),
      key("e", "editor (current failure)"),
      key("f", "edit tidex.conf"),
      "1-4  listed files",
      "arrows  scroll server",
      "left/right  cycle failures",
      key("g", "git sheet"),
      key("?", "this help"),
      key("q", "quit"),
      "esc closes"
    ]
  end

  defp git_sheet_lines(state) do
    git_status_lines(state.git) ++ git_log_lines(state)
  end

  defp git_log_lines(state) do
    lines =
      if state.output_source == :git do
        state.output_lines
      else
        state.git_log
      end

    case lines do
      [] -> []
      lines -> ["" | lines]
    end
  end

  defp hotkey(letter, word) do
    if String.starts_with?(word, letter) do
      Termex.bold(letter) <> String.replace_prefix(word, letter, "")
    else
      Termex.bold(letter) <> word
    end
  end

  defp key(letter, rest), do: Termex.bold(letter) <> "  " <> rest

  defp git_status_lines(%{status: text}) when is_binary(text) and text != "" do
    String.split(text, "\n")
  end

  defp git_status_lines(%{branch: nil}), do: ["(no repository)"]
  defp git_status_lines(_), do: ["(no status)"]
end
