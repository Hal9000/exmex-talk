defmodule Tidex.GitTest do
  use ExUnit.Case, async: true

  alias Tidex.Git

  test "snapshot reads branch and dirty count from this repo" do
    snapshot = Git.snapshot()
    assert is_binary(snapshot.branch)
    assert snapshot.branch != ""
    assert is_integer(snapshot.dirty)
    assert snapshot.dirty >= 0
  end

  test "poller sends snapshots to the notify process" do
    reader = fn -> %{branch: "topic", dirty: 2} end
    assert {:ok, pid} = Git.start_link(self(), reader: reader, interval: 50)
    assert_receive {:git, %{branch: "topic", dirty: 2}}, 200
    Git.stop(pid)
    refute Process.alive?(pid)
  end
end
