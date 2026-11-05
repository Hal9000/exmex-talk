defmodule Tidex.Resize do
  @moduledoc false

  @behaviour :gen_event

  @spec subscribe(pid()) :: {:ok, term()} | {:error, term()}
  def subscribe(pid) when is_pid(pid) do
    with {:unix, _name} <- :os.type(),
         signal_server when is_pid(signal_server) <- Process.whereis(:erl_signal_server),
         :ok <- enable_signal() do
      handler = {__MODULE__, pid}

      case :gen_event.add_handler(signal_server, handler, pid) do
        :ok -> {:ok, handler}
        error -> {:error, error}
      end
    else
      nil -> {:error, :signal_server_unavailable}
      _other -> {:error, :unsupported}
    end
  end

  @spec unsubscribe(term()) :: :ok
  def unsubscribe(nil), do: :ok

  def unsubscribe(handler) do
    case Process.whereis(:erl_signal_server) do
      pid when is_pid(pid) ->
        _ = :gen_event.delete_handler(pid, handler, :remove)
        :ok

      nil ->
        :ok
    end
  end

  @impl :gen_event
  def init(pid), do: {:ok, pid}

  @impl :gen_event
  def handle_event(:sigwinch, pid) do
    send(pid, :sigwinch)
    {:ok, pid}
  end

  def handle_event(_event, pid), do: {:ok, pid}

  @impl :gen_event
  def handle_call(_request, pid), do: {:ok, :ok, pid}

  @impl :gen_event
  def handle_info(_message, pid), do: {:ok, pid}

  @impl :gen_event
  def terminate(_reason, _pid), do: :ok

  @impl :gen_event
  def code_change(_old_version, pid, _extra), do: {:ok, pid}

  defp enable_signal do
    :os.set_signal(:sigwinch, :handle)
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
