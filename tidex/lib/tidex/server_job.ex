defmodule Tidex.ServerJob do
  @moduledoc """
  Owns one foreground project-server command and its OS process group.

  Server commands still use the shell syntax configured in `tidex.conf`,
  but erlexec places the shell and its descendants in a dedicated process
  group. Stopping the job sends TERM, waits, then escalates to KILL.
  """

  use GenServer

  @stop_timeout 3_000

  @type info :: %{os_pid: pos_integer(), group_id: pos_integer()}

  @spec start(String.t(), pid(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(command, notify, opts \\ [])
      when is_binary(command) and is_pid(notify) and is_list(opts) do
    ref = Keyword.fetch!(opts, :ref)

    spec = %{
      id: {:server_job, ref},
      start: {__MODULE__, :start_link, [command, notify, opts]},
      restart: :temporary,
      shutdown: @stop_timeout + 1_000
    }

    DynamicSupervisor.start_child(Tidex.Workers, spec)
  end

  @spec start_link(String.t(), pid(), keyword()) :: GenServer.on_start()
  def start_link(command, notify, opts) do
    GenServer.start_link(__MODULE__, {command, notify, opts})
  end

  @spec stop(pid() | nil) :: :ok | {:error, term()}
  def stop(nil), do: :ok

  def stop(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :stop, @stop_timeout + 1_000)
    else
      :ok
    end
  catch
    :exit, {:noproc, _} -> :ok
    :exit, reason -> {:error, reason}
  end

  @doc false
  @spec info(pid()) :: info()
  def info(pid), do: GenServer.call(pid, :info)

  @impl GenServer
  def init({command, notify, opts}) do
    ref = Keyword.fetch!(opts, :ref)
    cd = Keyword.get(opts, :cd)

    exec_opts = [
      :monitor,
      :stdout,
      {:stderr, :stdout},
      {:group, 0},
      :kill_group,
      {:kill_timeout, 1}
    ]

    exec_opts = if is_binary(cd), do: [{:cd, cd} | exec_opts], else: exec_opts

    case :exec.run(command, exec_opts) do
      {:ok, exec_pid, os_pid} ->
        {:ok,
         %{
           exec_pid: exec_pid,
           os_pid: os_pid,
           group_id: os_pid,
           notify: notify,
           ref: ref,
           buffer: ""
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:info, _from, state) do
    {:reply, %{os_pid: state.os_pid, group_id: state.group_id}, state}
  end

  def handle_call(:stop, _from, state) do
    case :exec.stop_and_wait(state.exec_pid, @stop_timeout) do
      {:error, reason} -> {:reply, {:error, reason}, state}
      _result -> {:stop, :normal, :ok, state}
    end
  end

  @impl GenServer
  def handle_info({:stdout, os_pid, data}, %{os_pid: os_pid} = state) do
    {:noreply, forward_output(state, data)}
  end

  def handle_info(
        {:DOWN, os_pid, :process, exec_pid, reason},
        %{
          os_pid: os_pid,
          exec_pid: exec_pid
        } = state
      ) do
    state = flush_buffer(state)
    send(state.notify, {:command, state.ref, :exit, exit_status(reason)})
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    if Process.alive?(state.exec_pid) do
      _ = :exec.stop_and_wait(state.exec_pid, @stop_timeout)
    end

    :ok
  end

  defp forward_output(state, data) do
    parts = String.split(state.buffer <> data, "\n")
    {lines, [buffer]} = Enum.split(parts, -1)

    Enum.each(lines, fn line ->
      send(state.notify, {:command, state.ref, :line, String.trim_trailing(line, "\r")})
    end)

    %{state | buffer: buffer}
  end

  defp flush_buffer(%{buffer: ""} = state), do: state

  defp flush_buffer(state) do
    send(state.notify, {:command, state.ref, :line, String.trim_trailing(state.buffer, "\r")})
    %{state | buffer: ""}
  end

  defp exit_status(:normal), do: 0
  defp exit_status({:exit_status, encoded}) when is_integer(encoded), do: decode_status(encoded)

  defp exit_status({:status, encoded}) when is_integer(encoded), do: decode_status(encoded)
  defp exit_status(_reason), do: 1

  defp decode_status(encoded) do
    case :exec.status(encoded) do
      {:status, status} -> status
      {:signal, signal, _core} when is_integer(signal) -> 128 + signal
      {:signal, _signal, _core} -> 1
    end
  end
end
