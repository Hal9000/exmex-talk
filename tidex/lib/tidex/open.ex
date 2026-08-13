defmodule Tidex.Open do
  @moduledoc """
  Launch a browser or editor. The editor inherits the TTY; Termex must
  have yielded cooked mode first.
  """

  @spec browser(String.t()) :: :ok
  def browser(url) when is_binary(url) do
    {cmd, args} = browser_cmd()
    spawn(fn -> System.cmd(cmd, args ++ [url], stderr_to_stdout: true) end)
    :ok
  end

  @spec editor(String.t()) :: :ok
  def editor(command) when is_binary(command) do
    executable = System.find_executable("sh") || "/bin/sh"

    port =
      Port.open(
        {:spawn_executable, executable},
        [:nouse_stdio, :exit_status, args: ["-c", command]]
      )

    receive do
      {^port, {:exit_status, _status}} -> :ok
    end
  end

  defp browser_cmd do
    cond do
      cmd = System.find_executable("xdg-open") -> {cmd, []}
      cmd = System.find_executable("open") -> {cmd, []}
      true -> {"echo", []}
    end
  end
end
