defmodule Tidex.Keyboard do
  @moduledoc """
  Supervised keyboard task. Temporary: the UI stops it while yielding
  the TTY to an editor, then starts a new one.
  """

  @spec start(Termex.Device.t(), pid()) :: {:ok, pid()}
  def start(device, notify) when is_pid(notify) do
    spec = %{
      id: {:keyboard, notify},
      start: {Termex.Keyboard, :start_link, [device, [notify: notify]]},
      restart: :temporary,
      shutdown: :brutal_kill
    }

    DynamicSupervisor.start_child(Tidex.Workers, spec)
  end

  @spec stop(pid() | nil) :: :ok
  def stop(nil), do: :ok

  def stop(pid) when is_pid(pid) do
    _ = DynamicSupervisor.terminate_child(Tidex.Workers, pid)
    :ok
  end
end
