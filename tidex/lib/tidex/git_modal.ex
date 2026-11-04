defmodule Tidex.GitModal do
  @moduledoc false

  alias Tidex.{Modal, Scroll}

  @spec modal(map(), Scroll.t()) :: Modal.t()
  def modal(state, scroll \\ :follow) do
    %Modal{
      kind: :git,
      title: title(state.git),
      lines: lines(state),
      commands:
        Enum.join(
          [
            Termex.bold("a") <> "  add -u",
            Termex.bold("c") <> "  commit",
            Termex.bold("p") <> "  push",
            "esc close"
          ],
          "   "
        ),
      scroll: scroll,
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
end
