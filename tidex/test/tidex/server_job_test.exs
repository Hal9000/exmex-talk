defmodule Tidex.ServerJobTest do
  use ExUnit.Case, async: false

  alias Tidex.ServerJob

  @fixtures Path.expand("../fixtures", __DIR__)

  test "streams output and reports a natural exit" do
    ref = make_ref()
    {:ok, job} = ServerJob.start("printf 'one\\ntwo\\n'; exit 7", self(), ref: ref)

    assert_receive {:command, ^ref, :line, "one"}, 1_000
    assert_receive {:command, ^ref, :line, "two"}, 1_000
    assert_receive {:command, ^ref, :exit, 7}, 1_000
    refute Process.alive?(job)
  end

  test "stopping a TCP server releases its port" do
    port = free_port()
    ref = make_ref()
    command = "elixir #{shell_quote(Path.join(@fixtures, "tcp_server"))} #{port}"
    {:ok, job} = ServerJob.start(command, self(), ref: ref)

    assert_receive {:command, ^ref, :line, "READY " <> _}, 2_000
    assert %{os_pid: os_pid, group_id: os_pid} = ServerJob.info(job)
    assert connectable?(port)

    assert :ok = ServerJob.stop(job)
    refute Process.alive?(job)
    assert wait_until(fn -> bindable?(port) end)
  end

  test "stopping kills descendants in the owned process group" do
    ref = make_ref()
    command = shell_quote(Path.join(@fixtures, "process_tree.sh"))
    {:ok, job} = ServerJob.start(command, self(), ref: ref)

    assert_receive {:command, ^ref, :line, "CHILD " <> child_text}, 1_000
    child = String.to_integer(child_text)
    %{os_pid: leader} = ServerJob.info(job)
    assert os_process_alive?(leader)
    assert os_process_alive?(child)

    assert :ok = ServerJob.stop(job)
    assert wait_until(fn -> not os_process_alive?(leader) end)
    assert wait_until(fn -> not os_process_alive?(child) end)
  end

  test "stop escalates to KILL when the process ignores TERM" do
    ref = make_ref()
    command = shell_quote(Path.join(@fixtures, "ignore_term.sh"))
    {:ok, job} = ServerJob.start(command, self(), ref: ref)

    assert_receive {:command, ^ref, :line, "READY " <> pid_text}, 1_000
    os_pid = String.to_integer(pid_text)
    assert os_process_alive?(os_pid)

    assert :ok = ServerJob.stop(job)
    assert wait_until(fn -> not os_process_alive?(os_pid) end)
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp connectable?(port) do
    case :gen_tcp.connect(~c"localhost", port, [:binary, active: false], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end

  defp bindable?(port) do
    case :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end

  defp os_process_alive?(pid) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  end

  defp wait_until(fun, attempts \\ 100)

  defp wait_until(fun, attempts) when is_function(fun, 0) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(20)
        wait_until(fun, attempts - 1)
    end
  end

  defp shell_quote(path), do: "'" <> String.replace(path, "'", "'\\''") <> "'"
end
