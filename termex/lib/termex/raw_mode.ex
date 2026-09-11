defmodule Termex.RawMode do
  @moduledoc """
  Puts a real terminal into single-key (non-canonical) input mode.

  OTP's native raw terminal is used when available. `stty` against
  `/dev/tty` is the fallback; tests and injected devices skip both paths.

  `yield/2` restores the original tty settings long enough to run an
  external editor, then re-enters raw mode.
  """

  alias Termex.Device

  @type session :: {:native | :stty, String.t() | nil} | nil

  @spec enter(Device.t()) :: {:ok, session()}
  def enter(%Device{input: input}) when input in [:stdio, :standard_io] do
    settings = saved_settings()

    case interactive_raw() do
      :ok ->
        {:ok, {:native, settings}}

      :unsupported ->
        case {settings, enable_raw()} do
          {settings, :ok} when is_binary(settings) -> {:ok, {:stty, settings}}
          _ -> {:ok, nil}
        end
    end
  end

  def enter(%Device{}), do: {:ok, nil}

  @spec leave(session()) :: :ok
  def leave(nil), do: :ok

  def leave({_mode, settings}) when is_binary(settings) do
    restore_tty(settings)
    :ok
  end

  def leave({_mode, nil}), do: :ok

  @spec with_raw_mode(Device.t(), (-> result) | (session() -> result)) :: result when result: var
  def with_raw_mode(device, fun) when is_function(fun, 0) do
    with_raw_mode(device, fn _session -> fun.() end)
  end

  def with_raw_mode(%Device{} = device, fun) when is_function(fun, 1) do
    {:ok, session} = enter(device)

    try do
      fun.(session)
    after
      leave(session)
    end
  end

  @doc """
  Temporarily restore cooked mode, run `fun`, then re-enable raw mode.

  `session` is the value returned by `enter/1` (`nil` when there is no TTY).
  """
  @spec yield(session(), (-> result)) :: result when result: var
  def yield(nil, fun), do: fun.()

  def yield({mode, settings}, fun) do
    if is_binary(settings), do: restore_tty(settings)

    try do
      fun.()
    after
      reenter(mode)
    end
  end

  defp saved_settings do
    case stty(["-g"]) do
      {settings, 0} -> String.trim(settings)
      _ -> nil
    end
  end

  defp interactive_raw do
    if Code.ensure_loaded?(:shell) and function_exported?(:shell, :start_interactive, 1) do
      case :shell.start_interactive({:noshell, :raw}) do
        :ok -> :ok
        {:error, _reason} -> :unsupported
      end
    else
      :unsupported
    end
  rescue
    _ -> :unsupported
  catch
    _, _ -> :unsupported
  end

  defp reenter(:native) do
    _ = configure(["-icanon", "-echo", "min", "1", "time", "0"])
    _ = :io.setopts(:standard_io, echo: false)
    :ok
  end

  defp reenter(:stty), do: enable_raw()

  defp enable_raw do
    # -icanon: one key at a time; -echo: don't print the key.
    # Ctrl-C still works, unlike full `stty raw`.
    configure(["-icanon", "-echo", "min", "1", "time", "0"])
  end

  defp restore_tty(settings) do
    configure([settings])
  end

  @doc false
  @spec configure([String.t()]) :: :ok | :error
  def configure(args) do
    case stty(args) do
      {_output, 0} -> :ok
      _ -> :error
    end
  end

  # System.cmd connects the child's stdin to a pipe. stty must instead
  # inspect the controlling terminal; shell redirection is portable across
  # macOS and Linux, whose stty device flags differ (-f versus -F).
  defp stty(args) do
    shell = System.find_executable("sh") || "/bin/sh"
    System.cmd(shell, ["-c", "stty \"$@\" < /dev/tty", "stty" | args], stderr_to_stdout: true)
  rescue
    _ -> :error
  end
end
