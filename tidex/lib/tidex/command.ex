defmodule Tidex.Command do
  @moduledoc """
  Runs a shell command and streams lines back to a notify process.

  Jobs are temporary children of `Tidex.Workers`. Messages:

      {:command, ref, :line, line}
      {:command, ref, :exit, status}
  """

  @spec start(String.t(), pid(), keyword()) :: {:ok, pid()}
  def start(command, notify, opts \\ []) when is_binary(command) and is_pid(notify) do
    ref = Keyword.fetch!(opts, :ref)
    cd = Keyword.get(opts, :cd)

    spec = %{
      id: {:command, ref},
      start: {Task, :start_link, [fn -> run(command, notify, ref, cd) end]},
      restart: :temporary,
      shutdown: :brutal_kill
    }

    DynamicSupervisor.start_child(Tidex.Workers, spec)
  end

  @spec stop(pid() | nil) :: :ok
  def stop(nil), do: :ok

  def stop(pid) when is_pid(pid) do
    case Process.whereis(Tidex.Workers) do
      nil ->
        Process.exit(pid, :kill)

      _ ->
        case DynamicSupervisor.terminate_child(Tidex.Workers, pid) do
          :ok -> :ok
          {:error, :not_found} -> Process.exit(pid, :kill)
        end
    end

    :ok
  end

  defp run(command, notify, ref, cd) do
    executable = System.find_executable("sh") || "/bin/sh"

    port_opts = [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      :hide,
      args: ["-c", command],
      line: 1024
    ]

    port_opts = if is_binary(cd), do: Keyword.put(port_opts, :cd, cd), else: port_opts

    port = Port.open({:spawn_executable, executable}, port_opts)

    listen(port, notify, ref)
  end

  defp listen(port, notify, ref) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        send(notify, {:command, ref, :line, line})
        listen(port, notify, ref)

      {^port, {:data, {:noeol, chunk}}} ->
        send(notify, {:command, ref, :line, chunk})
        listen(port, notify, ref)

      {^port, {:exit_status, status}} ->
        send(notify, {:command, ref, :exit, status})
    end
  end
end
