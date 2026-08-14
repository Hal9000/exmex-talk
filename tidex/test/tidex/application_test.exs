defmodule Tidex.ApplicationTest do
  use ExUnit.Case, async: false

  alias Tidex.{Command, FakeTerminal, Git, Keyboard}

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

    FakeTerminal.wait_until(fn ->
      git = Process.whereis(Tidex.Git)
      is_pid(git) and git != pid and Process.alive?(git)
    end)
  end

  test "command jobs run under the worker supervisor" do
    ref = make_ref()
    assert {:ok, pid} = Command.start("true", self(), ref: ref)
    children = DynamicSupervisor.which_children(Tidex.Workers)
    assert Enum.any?(children, fn {:undefined, child, :worker, _} -> child == pid end)
    assert_receive {:command, ^ref, :exit, 0}, 1000
  end

  test "Command.stop kills a live supervised job" do
    ref = make_ref()
    assert {:ok, pid} = Command.start("sleep 60", self(), ref: ref)
    assert Process.alive?(pid)
    assert :ok = Command.stop(pid)
    refute Process.alive?(pid)
  end

  test "keyboard tasks can be started and stopped under Workers" do
    {device, _out} = FakeTerminal.open("q")
    assert {:ok, pid} = Keyboard.start(device, self())
    assert Process.alive?(pid)
    assert_receive {:termex, :key, "q"}
    assert :ok = Keyboard.stop(pid)
    refute Process.alive?(pid)
  end

  test "poll_git subscribes the UI to the named git poller" do
    {ui, _device, out} =
      FakeTerminal.start_ui(
        poll_git: true,
        git_reader: fn -> %{branch: "wired", dirty: 9} end
      )

    on_exit(fn -> FakeTerminal.stop_ui(ui) end)

    FakeTerminal.wait_until(fn -> FakeTerminal.last_frame(out) =~ "wired" end)
    send(Process.whereis(Tidex.Git), :poll)
    %{branch: branch} = Git.snapshot()
    FakeTerminal.wait_until(fn -> FakeTerminal.last_frame(out) =~ branch end)
    FakeTerminal.stop_ui(ui)
  end

  test "q kills a running command job" do
    parent = self()

    runner = fn _cmd, _notify, _ref ->
      pid = spawn(fn -> Process.sleep(:infinity) end)
      send(parent, {:started, pid})
      {:ok, pid}
    end

    {ui, _device, _out} = FakeTerminal.start_ui(runner: runner, test_command: "mix test")
    on_exit(fn -> FakeTerminal.stop_ui(ui) end)

    send(ui, {:termex, :key, "t"})
    assert_receive {:started, pid}, 500
    assert Process.alive?(pid)

    FakeTerminal.stop_ui(ui)
    refute Process.alive?(pid)
  end

  test "git updates resume after the poller crashes when the UI is named" do
    {ui, _device, out} =
      FakeTerminal.start_ui(
        poll_git: true,
        name: Tidex.UI,
        git_reader: fn -> %{branch: "pre-crash", dirty: 0} end
      )

    on_exit(fn -> FakeTerminal.stop_ui(ui) end)

    FakeTerminal.wait_until(fn -> FakeTerminal.last_frame(out) =~ "pre-crash" end)

    pid = Process.whereis(Tidex.Git)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1000

    FakeTerminal.wait_until(fn ->
      git = Process.whereis(Tidex.Git)
      is_pid(git) and git != pid
    end)

    %{branch: branch} = Git.snapshot()
    FakeTerminal.wait_until(fn -> FakeTerminal.last_frame(out) =~ branch end)
    FakeTerminal.stop_ui(ui)
  end
end
