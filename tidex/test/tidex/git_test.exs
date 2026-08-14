defmodule Tidex.GitTest do
  use ExUnit.Case, async: true

  alias Tidex.Git

  test "snapshot reads branch, dirty count, and status from this repo" do
    snapshot = Git.snapshot()
    assert is_binary(snapshot.branch)
    assert snapshot.branch != ""
    assert is_integer(snapshot.dirty)
    assert snapshot.dirty >= 0
    assert is_binary(snapshot.status)
    assert snapshot.status =~ "On branch"
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
      assert Git.snapshot(dir) == %{branch: nil, dirty: 0, status: ""}
    after
      File.rm_rf!(dir)
    end
  end

  test "snapshot in a throwaway repo reports a dirty file and status text" do
    in_repo(fn dir ->
      snapshot = Git.snapshot(dir)
      assert snapshot.branch in ["main", "master"]
      assert snapshot.dirty >= 1
      assert snapshot.status =~ "On branch"
      assert snapshot.status =~ "modified" or snapshot.status =~ "Changes not staged"
    end)
  end

  test "git add -u in a throwaway repo stages the dirty file" do
    in_repo(fn dir ->
      {_, 0} = System.cmd("git", ["add", "-u"], cd: dir)
      snapshot = Git.snapshot(dir)
      assert snapshot.status =~ "Changes to be committed"
    end)
  end

  defp in_repo(fun) do
    dir = Path.join(System.tmp_dir!(), "tidex-git-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      git!(dir, ["init", "-b", "main"])
      git!(dir, ["config", "user.email", "tidex@example.test"])
      git!(dir, ["config", "user.name", "Tidex"])
      File.write!(Path.join(dir, "file.txt"), "one\n")
      git!(dir, ["add", "file.txt"])
      git!(dir, ["commit", "-m", "init"])
      File.write!(Path.join(dir, "file.txt"), "two\n")
      fun.(dir)
    after
      File.rm_rf!(dir)
    end
  end

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    out
  end
end
