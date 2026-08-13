defmodule Termex.Keyboard do
  @moduledoc """
  Reads keys from a device and sends them as messages.

  Implemented as a `Task` so Tidex can supervise it. The UI process owns
  rendering; this process only forwards keys:

      {:termex, :key, "q"}
      {:termex, :key, :eof}
  """

  alias Termex.Device

  @spec start_link(Device.t(), keyword()) :: {:ok, pid()}
  def start_link(%Device{} = device, opts \\ []) do
    notify = Keyword.get(opts, :notify, self())
    Task.start_link(fn -> loop(device, notify) end)
  end

  defp loop(device, notify) do
    case Termex.read_key(device) do
      :eof ->
        send(notify, {:termex, :key, :eof})

      key ->
        send(notify, {:termex, :key, key})
        loop(device, notify)
    end
  end
end
