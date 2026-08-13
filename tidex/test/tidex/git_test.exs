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

  test "subscribe and unsubscribe control who receives polls" do
    reader = fn -> %{branch: "sub", dirty: 0} end
    assert {:ok, git} = Git.start_link(name: nil, interval: 10_000, reader: reader)
    refute_receive {:git, _}, 50

    Git.subscribe(self(), git)
    send(git, :poll)
    assert_receive {:git, %{branch: "sub"}}, 200

    Git.unsubscribe(self(), git)
    send(git, :poll)
    refute_receive {:git, _}, 50
    Git.stop(git)
  end

  test "snapshot is empty outside a git repo" do
    dir = Path.join(System.tmp_dir!(), "tidex-nogit-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      File.cd!(dir, fn ->
        assert Git.snapshot() == %{branch: nil, dirty: 0}
      end)
    after
      File.rm_rf!(dir)
    end
  end
end
