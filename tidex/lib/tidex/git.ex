defmodule Tidex.Git do
  @moduledoc """
  Branch name, dirty count, and untracked count. A supervised GenServer
  polls git and sends `{:git, snapshot}` to the UI; it never draws.

  The poller snapshots the directory given to `watch/2`: the open project,
  even when that project is not the process working directory. Until then
  it stays quiet, so the launch directory is not reported in its place.
  """

  use GenServer

  @type snapshot :: %{
          root: String.t() | nil,
          branch: String.t() | nil,
          dirty: non_neg_integer(),
          untracked: non_neg_integer(),
          status: String.t()
        }

  @spec snapshot(String.t()) :: snapshot()
  def snapshot(cwd \\ File.cwd!()) do
    case git(["rev-parse", "--show-toplevel"], cwd) do
      {:ok, root} ->
        branch =
          case git(["rev-parse", "--abbrev-ref", "HEAD"], cwd) do
            {:ok, branch} -> String.trim(branch)
            :error -> nil
          end

        {dirty, untracked} =
          case git(["status", "--porcelain"], cwd) do
            {:ok, out} -> counts(out)
            :error -> {0, 0}
          end

        status =
          case git(["status"], cwd) do
            {:ok, out} -> String.trim_trailing(out)
            :error -> ""
          end

        %{
          root: root |> String.trim() |> Path.expand(),
          branch: branch,
          dirty: dirty,
          untracked: untracked,
          status: status
        }

      :error ->
        empty()
    end
  end

  @doc false
  @spec empty() :: snapshot()
  def empty, do: %{root: nil, branch: nil, dirty: 0, untracked: 0, status: ""}

  @watch_key :git_dir

  @doc false
  @spec counts(String.t()) :: {non_neg_integer(), non_neg_integer()}
  def counts(porcelain) when is_binary(porcelain) do
    porcelain
    |> String.split("\n", trim: true)
    |> Enum.reduce({0, 0}, fn line, {dirty, untracked} ->
      if String.starts_with?(line, "??") do
        {dirty, untracked + 1}
      else
        {dirty + 1, untracked}
      end
    end)
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name_opts(name))
  end

  @spec start_link(pid(), keyword()) :: GenServer.on_start()
  def start_link(notify, opts) when is_pid(notify) and is_list(opts) do
    start_link(Keyword.merge(opts, notify: notify, name: nil))
  end

  @spec watch(String.t(), GenServer.server()) :: :ok
  def watch(dir, server \\ __MODULE__) when is_binary(dir) do
    dir = Path.expand(dir)

    if named_server?(server) do
      Application.put_env(:tidex, @watch_key, dir)
    end

    if running?(server), do: GenServer.call(server, {:watch, dir})
    :ok
  end

  @spec subscribe(pid(), GenServer.server()) :: :ok
  def subscribe(pid, server \\ __MODULE__) when is_pid(pid) do
    GenServer.cast(server, {:subscribe, pid})
  end

  @spec unsubscribe(pid(), GenServer.server()) :: :ok
  def unsubscribe(pid, server \\ __MODULE__) when is_pid(pid) do
    if running?(server), do: GenServer.cast(server, {:unsubscribe, pid}), else: :ok
  end

  @spec stop(pid() | nil) :: :ok
  def stop(nil), do: :ok

  def stop(pid) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000), else: :ok
  catch
    :exit, _ -> :ok
  end

  @impl GenServer
  def init(opts) do
    reader = Keyword.get(opts, :reader)
    interval = Keyword.get(opts, :interval, 2000)
    notify = Keyword.get(opts, :notify)

    state = %{reader: reader, dir: initial_dir(opts), interval: interval, notify: notify}
    send(self(), :poll)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:watch, dir}, _from, state) do
    {:reply, :ok, %{state | dir: dir}}
  end

  @impl GenServer
  def handle_cast({:subscribe, pid}, state) do
    {:noreply, %{state | notify: pid}}
  end

  def handle_cast({:unsubscribe, pid}, %{notify: pid} = state) do
    {:noreply, %{state | notify: nil}}
  end

  def handle_cast({:unsubscribe, _pid}, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(:poll, state) do
    case read(state) do
      :unwatched ->
        :ok

      snapshot ->
        if target = target(state), do: send(target, {:git, snapshot})
    end

    Process.send_after(self(), :poll, state.interval)
    {:noreply, state}
  end

  defp target(%{notify: pid}) when is_pid(pid), do: pid
  defp target(_state), do: Process.whereis(Tidex.UI)

  defp initial_dir(opts) do
    cond do
      Keyword.has_key?(opts, :dir) -> Keyword.get(opts, :dir)
      named_poller?() -> Application.get_env(:tidex, @watch_key)
      true -> nil
    end
  end

  defp read(%{reader: reader}) when is_function(reader, 0), do: reader.()

  defp read(state) do
    case current_dir(state) do
      dir when is_binary(dir) -> snapshot(dir)
      _ -> :unwatched
    end
  end

  defp current_dir(state) do
    cond do
      named_poller?() -> Application.get_env(:tidex, @watch_key) || state.dir
      is_binary(state.dir) -> state.dir
      true -> nil
    end
  end

  defp named_server?(server) do
    server == __MODULE__ or (is_pid(server) and server == Process.whereis(__MODULE__))
  end

  defp named_poller?, do: self() == Process.whereis(__MODULE__)

  defp running?(server) when is_atom(server), do: Process.whereis(server) != nil
  defp running?(server) when is_pid(server), do: Process.alive?(server)

  defp name_opts(nil), do: []
  defp name_opts(name), do: [name: name]

  defp git(args, cwd) do
    case System.cmd("git", args, stderr_to_stdout: true, cd: cwd, env: [{"LC_ALL", "C"}]) do
      {out, 0} -> {:ok, out}
      _ -> :error
    end
  rescue
    _ -> :error
  end
end
