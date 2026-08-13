defmodule Tidex.View do
  @moduledoc false

  alias Tidex.State

  @spec render(Termex.Device.t(), State.t()) :: :ok
  def render(device, %State{} = state) do
    Termex.clear_visible(device)
    Termex.move(device, 1, 1)

    Termex.write_at(device, 1, 1, state.title)
    Termex.write_at(device, 3, 1, "project: #{state.project_name}")

    state.statuses
    |> Enum.with_index()
    |> Enum.each(fn {{label, value}, index} ->
      Termex.write_at(device, 4 + index, 1, "#{pad_label(label)} #{value}")
    end)

    Termex.write_at(device, 7, 1, "output:")
    write_output(device, 8, state.command_output)

    Termex.write_at(device, 18, 1, "[t] run command   [q] quit")
    :ok
  end

  defp pad_label(label) do
    String.pad_trailing("#{label}:", 8)
  end

  defp write_output(device, start_row, output) do
    output
    |> String.split("\n")
    |> Enum.take(8)
    |> Enum.with_index()
    |> Enum.each(fn {line, index} ->
      Termex.write_at(device, start_row + index, 1, line)
    end)
  end
end
