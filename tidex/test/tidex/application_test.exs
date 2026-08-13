defmodule Tidex.ApplicationTest do
  use ExUnit.Case, async: false

  test "starts a supervisor, worker supervisor, and git poller" do
    assert Process.whereis(Tidex.Supervisor)
    assert Process.whereis(Tidex.Workers)
    assert Process.whereis(Tidex.Git)
  end

  test "git poller is restarted if it crashes" do
    pid = Process.whereis(Tidex.Git)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1000

    Tidex.FakeTerminal.wait_until(fn ->
      git = Process.whereis(Tidex.Git)
      is_pid(git) and git != pid and Process.alive?(git)
    end)
  end

  test "command jobs run under the worker supervisor" do
    ref = make_ref()
    assert {:ok, pid} = Tidex.Command.start("true", self(), ref: ref)
    children = DynamicSupervisor.which_children(Tidex.Workers)
    assert Enum.any?(children, fn {:undefined, child, :worker, _} -> child == pid end)
    assert_receive {:command, ^ref, :exit, 0}, 1000
  end
end
