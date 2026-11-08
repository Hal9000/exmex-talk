defmodule Tidex.GitInfoTest do
  use ExUnit.Case, async: true

  alias Tidex.GitInfo

  test "summarizes branch and number-first counts" do
    modal = GitInfo.modal(%{branch: "main", dirty: 1, untracked: 0})

    assert modal.kind == :git_info
    assert modal.lines == ["branch: main", "1 tracked change", "0 untracked files"]
    assert modal.commands == "esc close"
  end

  test "reports the absence of a repository" do
    modal = GitInfo.modal(%{branch: nil, dirty: 0, untracked: 0})
    assert modal.lines == ["No Git repository"]
  end
end
