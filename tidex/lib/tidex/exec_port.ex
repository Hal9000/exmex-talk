defmodule Tidex.ExecPort do
  @moduledoc false

  @arch :erlang.system_info(:system_architecture) |> List.to_string()
  @source Path.expand("../../deps/erlexec/priv/#{@arch}/exec-port", __DIR__)
  @external_resource @source
  @binary File.read!(@source)
  @raw_digest :crypto.hash(:sha256, @binary)
  @digest Base.encode16(@raw_digest, case: :lower)

  @spec start_link() :: GenServer.on_start()
  def start_link do
    :exec.start_link(portexe: executable_path())
  end

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{
      id: :exec,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      shutdown: 10_000
    }
  end

  @doc false
  @spec executable_path() :: String.t()
  def executable_path do
    dir = Path.join(cache_home(), "tidex/#{@arch}")
    path = Path.join(dir, "exec-port-#{@digest}")

    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    materialize(path)
    path
  end

  defp materialize(path) do
    if valid?(path) do
      File.chmod!(path, 0o700)
    else
      nonce = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
      tmp = "#{path}.#{System.pid()}.#{nonce}"
      {:ok, file} = File.open(tmp, [:write, :binary, :exclusive])
      :ok = IO.binwrite(file, @binary)
      :ok = File.close(file)
      File.chmod!(tmp, 0o700)

      case File.rename(tmp, path) do
        :ok -> :ok
        {:error, :eexist} -> File.rm!(tmp)
        {:error, reason} -> raise File.Error, reason: reason, action: "rename", path: path
      end

      File.chmod!(path, 0o700)
    end
  end

  defp valid?(path) do
    case File.read(path) do
      {:ok, binary} -> :crypto.hash(:sha256, binary) == @raw_digest
      _ -> false
    end
  end

  defp cache_home do
    System.get_env("XDG_CACHE_HOME") ||
      case System.user_home() do
        home when is_binary(home) -> Path.join(home, ".cache")
        _ -> System.tmp_dir!()
      end
  end
end
