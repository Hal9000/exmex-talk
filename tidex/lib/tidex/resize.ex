defmodule Tidex.Resize do
  @moduledoc false

  @behaviour :gen_event

  @spec subscribe(pid()) :: {:ok, term()} | {:error, term()}
  def subscribe(pid) when is_pid(pid) do
    handler = {__MODULE__, pid}

    with :ok <- enable_signal(),
         :ok <- add_handler(handler, pid) do
      {:ok, handler}
    end
  end

  @spec unsubscribe(term()) :: :ok
  def unsubscribe(nil), do: :ok

  def unsubscribe(handler) do
    safely(fn -> :gen_event.delete_handler(:erl_signal_server, handler, :remove) end)
    :ok
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
    case safely(fn -> :os.set_signal(:sigwinch, :handle) end) do
      :ok -> :ok
      other -> {:error, other}
    end
  end

  defp add_handler(handler, pid) do
    case safely(fn -> :gen_event.add_handler(:erl_signal_server, handler, pid) end) do
      :ok -> :ok
      other -> {:error, other}
    end
  end

  defp safely(fun) do
    fun.()
  catch
    kind, reason -> {kind, reason}
  end
end
