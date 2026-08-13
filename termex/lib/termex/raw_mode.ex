defmodule Termex.RawMode do
  @moduledoc """
  Puts a real terminal into single-key (non-canonical) input mode.

  Tests and piped stdin skip this path: `stty` fails when there is no TTY,
  and injected devices are left unchanged.
  """

  alias Termex.Device

  @spec with_raw_mode(Device.t(), (-> result)) :: result when result: var
  def with_raw_mode(%Device{input: input}, fun) when input in [:stdio, :standard_io] do
    case save_tty() do
      {:ok, settings} ->
        enable_raw()

        try do
          fun.()
        after
          restore_tty(settings)
        end

      :error ->
        fun.()
    end
  end

  def with_raw_mode(%Device{}, fun), do: fun.()

  defp save_tty do
    case System.cmd("stty", ["-g"], stderr_to_stdout: true) do
      {settings, 0} -> {:ok, String.trim(settings)}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp enable_raw do
    # -icanon: one key at a time; -echo: don't print the key.
    # Ctrl-C still works, unlike full `stty raw`.
    System.cmd("stty", ["-icanon", "-echo", "min", "1", "time", "0"], stderr_to_stdout: true)
  end

  defp restore_tty(settings) do
    System.cmd("stty", [settings], stderr_to_stdout: true)
  end
end
