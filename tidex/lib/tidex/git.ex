defmodule Tidex.Git do
  @moduledoc """
  Branch name and dirty-file count. A poller sends `{:git, snapshot}` to
  the UI process; it never draws.
  """

  @type snapshot :: %{branch: String.t() | nil, dirty: non_neg_integer()}

  @spec snapshot() :: snapshot()
  def snapshot do
    case git(["rev-parse", "--abbrev-ref", "HEAD"]) do
      {:ok, branch} ->
        dirty =
          case git(["status", "--porcelain"]) do
            {:ok, ""} -> 0
            {:ok, out} -> length(String.split(out, "\n", trim: true))
            :error -> 0
          end

        %{branch: String.trim(branch), dirty: dirty}

      :error ->
        %{branch: nil, dirty: 0}
    end
  end

  @spec start_link(pid(), keyword()) :: {:ok, pid()}
  def start_link(notify, opts \\ []) when is_pid(notify) do
    interval = Keyword.get(opts, :interval, 2000)
    reader = Keyword.get(opts, :reader, &snapshot/0)

    pid =
      spawn(fn ->
        send(notify, {:git, reader.()})
        loop(notify, reader, interval)
      end)

    {:ok, pid}
  end

  @spec stop(pid() | nil) :: :ok
  def stop(nil), do: :ok

  def stop(pid) when is_pid(pid) do
    Process.exit(pid, :kill)
    :ok
  end

  defp loop(notify, reader, interval) do
    Process.sleep(interval)
    send(notify, {:git, reader.()})
    loop(notify, reader, interval)
  end

  defp git(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      _ -> :error
    end
  rescue
    _ -> :error
  end
end
