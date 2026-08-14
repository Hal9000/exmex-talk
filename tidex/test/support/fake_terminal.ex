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

  @doc """
  Bytes written after the last CSI `2J` (clear visible).

  StringIO never forgets earlier frames. Tidex clears the screen at the
  start of every draw, so the last frame is what would be on a TTY.
  """
  @spec last_frame(pid() | String.t()) :: String.t()
  def last_frame(output_dev) when is_pid(output_dev), do: last_frame(text(output_dev))

  def last_frame(text) when is_binary(text) do
    text
    |> String.split("\e[2J")
    |> List.last()
  end

  @doc """
  Last-frame text with CSI removed (visible characters only).
  """
  @spec visible(pid() | String.t()) :: String.t()
  def visible(source), do: source |> last_frame() |> Termex.ANSI.strip()

  @doc """
  Text written into `pane` in the last frame, top to bottom.

  Uses the pane's row/col/height (Termex writes one clipped line per
  row at `col`). Later writes to the same cell win, matching a TTY.
  SGR in a cell is stripped so tests assert on visible text.
  """
  @spec region_lines(pid() | String.t(), Tidex.Layout.Pane.t()) :: [String.t()]
  def region_lines(source, %Tidex.Layout.Pane{} = pane) do
    last_row = pane.row + pane.height - 1

    source
    |> writes()
    |> Enum.reduce(%{}, fn {row, col, body}, acc ->
      if col == pane.col and row >= pane.row and row <= last_row do
        Map.put(acc, row, body)
      else
        acc
      end
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp writes(source) do
    frame = last_frame(source)

    frame
    |> then(&Regex.split(~r/(\e\[\d+;\d+H)/, &1, include_captures: true, trim: true))
    |> parse_writes([])
    |> Enum.reverse()
  end

  defp parse_writes([], acc), do: acc

  defp parse_writes([marker], acc) do
    case cursor(marker) do
      {row, col} -> [{row, col, ""} | acc]
      :no -> acc
    end
  end

  defp parse_writes([marker, body | rest], acc) do
    case cursor(marker) do
      {row, col} ->
        {visible, rest} = take_body(body, rest)
        parse_writes(rest, [{row, col, visible} | acc])

      :no ->
        parse_writes([body | rest], acc)
    end
  end

  defp take_body(body, rest) do
    case cursor(body) do
      {_, _} -> {"", [body | rest]}
      :no -> {Termex.ANSI.strip(body), rest}
    end
  end

  defp cursor(text) do
    case Regex.run(~r/\A\e\[(\d+);(\d+)H\z/, text) do
      [_, row, col] -> {String.to_integer(row), String.to_integer(col)}
      _ -> :no
    end
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
          width: 80,
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
