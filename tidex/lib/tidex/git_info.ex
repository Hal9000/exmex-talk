defmodule Tidex.GitInfo do
  @moduledoc false

  alias Tidex.Modal

  @spec modal(Tidex.Git.snapshot()) :: Modal.t()
  def modal(git) do
    %Modal{
      kind: :git_info,
      title: "git info",
      lines: lines(git),
      commands: "esc close",
      max_width: 64,
      max_height: 7,
      min_width: 36,
      min_height: 5
    }
  end

  defp lines(%{branch: branch} = git) when is_binary(branch) do
    [
      "branch: #{branch}",
      count(Map.get(git, :dirty, 0), "tracked change"),
      count(Map.get(git, :untracked, 0), "untracked file")
    ]
  end

  defp lines(_git), do: ["No Git repository"]

  defp count(1, label), do: "1 #{label}"
  defp count(number, label), do: "#{number} #{label}s"
end
