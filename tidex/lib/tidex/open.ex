defmodule Tidex.Open do
  @moduledoc """
  Launch a browser or editor. The editor inherits the TTY; Termex must
  have yielded cooked mode first.
  """

  @vim_family ~w(vi vim nvim)
  @known ~w(vi vim nvim emacs code hx)

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

  @doc """
  Build the shell command to open `file` (and optional `line`).

  A command that already contains `{file}` / `{line}` is treated as a
  template. A bare known editor name gets that editor's jump flags.
  Unknown editors get `{cmd} {file}`. With no file, `editor` is unchanged.
  """
  @spec editor_command(String.t(), keyword()) :: String.t()
  def editor_command(editor, opts \\ []) when is_binary(editor) do
    editor = String.trim(editor)
    file = Keyword.get(opts, :file)
    line = Keyword.get(opts, :line)
    file = if is_binary(file) and file != "", do: file

    cond do
      template?(editor) and file -> interpolate(editor, file, line)
      file && line && bare_known?(editor) -> jump(editor, file, line)
      file && editor != "" -> "#{editor} #{quote_path(file)}"
      true -> editor
    end
  end

  defp template?(editor),
    do: String.contains?(editor, "{file}") or String.contains?(editor, "{line}")

  defp bare_known?(editor) do
    basename(editor) in @known and not String.contains?(String.trim(editor), " ")
  end

  defp jump(editor, file, line) do
    case basename(editor) do
      name when name in @vim_family -> "#{editor} +#{line} #{quote_path(file)}"
      "emacs" -> "#{editor} +#{line} #{quote_path(file)}"
      "code" -> "#{editor} -g #{quote_path("#{file}:#{line}")}"
      "hx" -> "#{editor} #{quote_path("#{file}:#{line}")}"
    end
  end

  defp interpolate(template, file, line) do
    quoted = quote_path(file)

    if line do
      template
      |> String.replace("{file}", quoted)
      |> String.replace("{line}", Integer.to_string(line))
    else
      template
      |> String.replace(~r/\s*\+\{line\}/, "")
      |> String.replace("{line}", "")
      |> String.replace("{file}", quoted)
      |> String.trim()
    end
  end

  defp basename(editor) do
    editor
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> hd()
    |> Path.basename()
  end

  defp quote_path(path) do
    "'" <> String.replace(path, "'", "'\\''") <> "'"
  end

  defp browser_cmd do
    cond do
      cmd = System.find_executable("xdg-open") -> {cmd, []}
      cmd = System.find_executable("open") -> {cmd, []}
      true -> {"echo", []}
    end
  end
end
