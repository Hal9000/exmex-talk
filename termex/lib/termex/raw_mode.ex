defmodule Termex.RawMode do
  @moduledoc """
  Puts a real terminal into single-key (non-canonical) input mode.

  Tests and piped stdin skip this path: `stty` fails when there is no TTY,
  and injected devices are left unchanged.

  `yield/2` restores the original tty settings long enough to run an
  external editor, then re-enters raw mode.
  """

  alias Termex.Device

  @type session :: String.t() | nil

  @spec with_raw_mode(Device.t(), (-> result) | (session() -> result)) :: result when result: var
  def with_raw_mode(device, fun) when is_function(fun, 0) do
    with_raw_mode(device, fn _session -> fun.() end)
  end

  def with_raw_mode(%Device{input: input}, fun)
      when is_function(fun, 1) and input in [:stdio, :standard_io] do
    case save_tty() do
      {:ok, settings} ->
        enable_raw()

        try do
          fun.(settings)
        after
          restore_tty(settings)
        end

      :error ->
        fun.(nil)
    end
  end

  def with_raw_mode(%Device{}, fun) when is_function(fun, 1), do: fun.(nil)

  @doc """
  Temporarily restore cooked mode, run `fun`, then re-enable raw mode.

  `session` is the value passed to the `with_raw_mode/2` callback (`nil`
  when there is no TTY).
  """
  @spec yield(session(), (-> result)) :: result when result: var
  def yield(nil, fun), do: fun.()

  def yield(settings, fun) when is_binary(settings) do
    restore_tty(settings)

    try do
      fun.()
    after
      enable_raw()
    end
  end

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
