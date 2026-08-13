defmodule Tidex.FakeTerminal do
  @moduledoc false

  @spec open(String.t()) :: {Termex.Device.t(), pid()}
  def open(input \\ "") do
    {:ok, input_dev} = StringIO.open(input)
    {:ok, output_dev} = StringIO.open("")
    {Termex.Device.pair(input_dev, output_dev), output_dev}
  end

  @spec text(pid()) :: String.t()
  def text(output_dev) do
    {_input, output} = StringIO.contents(output_dev)
    output
  end

  @spec start_ui(keyword()) :: {pid(), Termex.Device.t(), pid()}
  def start_ui(opts \\ []) do
    {device, out} = open()
    parent = self()

    opts =
      Keyword.merge(
        [
          device: device,
          keys: :none,
          notify_ready: parent,
          width: 40,
          height: 20,
          name: nil
        ],
        opts
      )

    {:ok, ui} = Tidex.UI.start_link(opts)

    receive do
      {:ready, ^ui} -> {ui, device, out}
    after
      1000 -> raise "Tidex UI did not start"
    end
  end

  @spec stop_ui(pid()) :: :ok
  def stop_ui(ui) do
    if Process.alive?(ui) do
      send(ui, {:termex, :key, "q"})
      wait_until(fn -> not Process.alive?(ui) end)
    end

    :ok
  end

  @spec wait_until((-> boolean()), pos_integer()) :: :ok
  def wait_until(fun, timeout_ms \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait(fun, deadline)
  end

  defp do_wait(fun, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        raise "timed out waiting for UI condition"
      end

      Process.sleep(10)
      do_wait(fun, deadline)
    end
  end
end
