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
    end

    render_footer(device, layout)
    render_sheet(device, state)
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
      "",
      pad("Test", col) <> "Server",
      pad("#{state.test_state}", col) <> "#{state.server_state}",
      "",
      "Git"
      | git_lobby_lines(state.git)
    ]
  end

  defp pad(text, width) do
    String.pad_trailing(text, width)
  end

  defp git_lobby_lines(%{branch: nil}), do: ["(no repository)"]

  defp git_lobby_lines(git) do
    [git.branch]
    |> append_count(Map.get(git, :dirty, 0), "dirty")
    |> append_count(Map.get(git, :untracked, 0), "untracked")
  end

  defp append_count(lines, n, _label) when n in [0, nil], do: lines
  defp append_count(lines, n, label), do: lines ++ ["#{n} #{label}"]

  defp render_fail(_device, _state, nil), do: :ok

  defp render_fail(device, state, pane) do
    current = Tidex.Failures.current(state)
    n = length(state.failures)
    index = rem(state.failure_index, max(n, 1)) + 1
    Termex.box(device, pane.row, pane.col, pane.width, pane.height, title: "fail #{index}/#{n}")
    inner = Layout.inner(pane)

    Termex.write_region(
      device,
      inner.row,
      inner.col,
      inner.width,
      inner.height,
      fail_lines(current)
    )
  end

  defp fail_lines(nil), do: []

  defp fail_lines(failure) do
    loc =
      case failure do
        %{file: file, line: line} when is_binary(file) and is_integer(line) -> "#{file}:#{line}"
        %{file: file} when is_binary(file) -> file
        _ -> ""
      end

    [failure.name, Enum.join(Enum.reject([loc, failure.snippet], &(&1 == "")), "  ")]
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

  defp render_footer(device, layout) do
    Termex.write_clipped(
      device,
      layout.footer_row - 1,
      1,
      layout.width,
      Enum.join(
        [hotkey("t", "test"), hotkey("s", "start"), hotkey("x", "stop"), hotkey("b", "browse")],
        " "
      )
    )

    Termex.write_clipped(
      device,
      layout.footer_row,
      1,
      layout.width,
      Enum.join(
        [hotkey("e", "edit"), hotkey("g", "git"), hotkey("?", "help"), hotkey("q", "quit")],
        " "
      )
    )
  end

  defp render_sheet(_device, %{overlay: nil}), do: :ok

  defp render_sheet(device, %{overlay: :test} = state) do
    sheet = Layout.sheet(state)
    render_fail(device, state, sheet.fail)
    render_log(device, state, sheet.log, "test · #{state.test_state}")
  end

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
      key("t", "test sheet (again to run)"),
      key("s", "server sheet (again to start)"),
      key("x", "stop server"),
      key("b", "open browser"),
      key("e", "editor (failure file)"),
      "arrows  scroll sheet",
      "left/right  cycle failures",
      key("g", "git sheet"),
      key("?", "this help"),
      key("q", "quit"),
      "esc closes"
    ]
  end

  defp git_sheet_lines(state) do
    [
      Enum.join(
        [hotkey("a", "add") <> " -u  ", hotkey("c", "commit") <> "  ", hotkey("p", "push")],
        ""
      ),
      "esc or g closes",
      ""
      | git_status_lines(state.git) ++ git_log_lines(state)
    ]
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
