defmodule Tidex.GitModal do
  @moduledoc false

  alias Tidex.{Modal, Scroll}

  @message_view_width 50

  @spec modal(map(), Scroll.t()) :: Modal.t()
  def modal(state, scroll \\ :follow) do
    %Modal{
      kind: :git,
      title: title(state.git),
      lines: lines(state),
      page: :status,
      commands:
        Enum.join(
          [
            Termex.bold("a") <> "  add -u",
            Termex.bold("c") <> "  commit",
            Termex.bold("l") <> "  pull",
            Termex.bold("p") <> "  push",
            Termex.bold("u") <> "  ship",
            "esc close"
          ],
          "  "
        ),
      scroll: scroll,
      min_width: 60,
      max_width: 64,
      min_height: 10,
      max_height: 12
    }
  end

  @spec commit(map(), String.t(), Scroll.t()) :: Modal.t()
  def commit(state, message \\ "", return_scroll \\ :follow) do
    prompt(state, :commit, message, return_scroll)
  end

  @spec ship(map(), String.t(), Scroll.t()) :: Modal.t()
  def ship(state, message \\ "", return_scroll \\ :follow) do
    prompt(state, :ship, message, return_scroll)
  end

  defp prompt(state, action, message, return_scroll) do
    %Modal{
      kind: :git,
      title: title(state.git),
      lines: lines(state) ++ ["", commit_prompt(message)],
      page: {action, message, return_scroll},
      commands: "enter #{action}   esc cancel",
      scroll: :follow,
      min_width: 60,
      max_width: 64,
      min_height: 10,
      max_height: 12
    }
  end

  @spec scroll(Modal.t(), term(), %{width: pos_integer(), height: pos_integer()}) :: Modal.t()
  def scroll(%Modal{kind: :git} = modal, key, screen) do
    body_height = Modal.body_height(screen, modal)

    delta =
      case key do
        :up -> -1
        :down -> 1
        :page_up -> -max(body_height, 1)
        :page_down -> max(body_height, 1)
      end

    %{modal | scroll: Scroll.step(modal.lines, body_height, modal.scroll, delta)}
  end

  defp title(%{branch: branch}) when is_binary(branch), do: "git · #{branch}"
  defp title(_git), do: "git"

  defp lines(state) do
    status_lines(state.git) ++ command_lines(state.git_log)
  end

  defp status_lines(%{status: status}) when is_binary(status) and status != "" do
    String.split(status, "\n")
  end

  defp status_lines(%{branch: nil}), do: ["(no repository)"]
  defp status_lines(%{branch: branch}) when is_binary(branch), do: ["On branch #{branch}"]
  defp status_lines(_git), do: ["(no status)"]

  defp command_lines([]), do: []
  defp command_lines(lines), do: ["", "command output" | lines]

  defp commit_prompt(message) do
    graphemes = String.graphemes(message)

    visible =
      if length(graphemes) <= @message_view_width do
        message
      else
        "…" <> (graphemes |> Enum.take(-(@message_view_width - 1)) |> Enum.join())
      end

    "Message: #{visible}▏"
  end
end
