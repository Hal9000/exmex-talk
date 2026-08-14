defmodule Tidex.Config do
  @moduledoc """
  Project label and commands from `tidex.conf`, walking from cwd toward `/`.

  Lines are `key: value`. `#` comments and blank lines are ignored.
  Known keys: `project`, `test`, `server`, `browser`, `editor`.
  """

  @filename "tidex.conf"
  @keys ~w(project test server browser editor)

  defstruct project: "tidex",
            test: "mix test",
            server: "python3 -m http.server 4000",
            browser: "http://localhost:4000",
            editor: "vi"

  @type t :: %__MODULE__{
          project: String.t(),
          test: String.t(),
          server: String.t(),
          browser: String.t(),
          editor: String.t()
        }

  @spec load(String.t()) :: t()
  def load(cwd \\ File.cwd!()) do
    cwd = Path.expand(cwd)

    case find_file(cwd) do
      nil ->
        defaults(cwd)

      path ->
        root = Path.dirname(path)
        merge(defaults(root), parse(File.read!(path)))
    end
  end

  @spec defaults(String.t()) :: t()
  def defaults(cwd \\ File.cwd!()) do
    cwd = Path.expand(cwd)

    %__MODULE__{
      project: default_project(cwd),
      test: default_test_command(cwd),
      server: "python3 -m http.server 4000",
      browser: "http://localhost:4000",
      editor: default_editor()
    }
  end

  @spec default_project(String.t()) :: String.t()
  def default_project(cwd \\ File.cwd!()) do
    cwd |> Path.expand() |> Path.basename()
  end

  @spec default_test_command(String.t()) :: String.t()
  def default_test_command(cwd \\ File.cwd!()) do
    cond do
      File.exists?(Path.join(cwd, "mix.exs")) -> "mix test"
      File.exists?(Path.join(cwd, "package.json")) -> "npm test"
      File.exists?(Path.join(cwd, "Cargo.toml")) -> "cargo test"
      File.exists?(Path.join(cwd, "go.mod")) -> "go test ./..."
      true -> "echo no test runner found"
    end
  end

  @spec default_editor() :: String.t()
  def default_editor do
    System.get_env("VISUAL") || System.get_env("EDITOR") || "vi"
  end

  @spec find_file(String.t()) :: String.t() | nil
  def find_file(dir) do
    dir = Path.expand(dir)
    path = Path.join(dir, @filename)

    cond do
      File.exists?(path) ->
        path

      true ->
        parent = Path.dirname(dir)
        if parent == dir, do: nil, else: find_file(parent)
    end
  end

  @spec parse(String.t()) :: %{optional(String.t()) => String.t()}
  def parse(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.reduce(%{}, &parse_line/2)
  end

  defp parse_line(line, acc) do
    line = String.trim(line)

    cond do
      line == "" or String.starts_with?(line, "#") ->
        acc

      true ->
        case String.split(line, ":", parts: 2) do
          [key, value] ->
            key = String.trim(key)
            value = value |> String.trim() |> unwrap()

            if key in @keys and value != "" do
              Map.put(acc, key, value)
            else
              acc
            end

          _ ->
            acc
        end
    end
  end

  defp unwrap(value) do
    cond do
      quoted?(value, "\"") -> String.slice(value, 1..-2//1)
      quoted?(value, "'") -> String.slice(value, 1..-2//1)
      true -> value
    end
  end

  defp quoted?(value, q) do
    String.length(value) >= 2 and String.starts_with?(value, q) and String.ends_with?(value, q)
  end

  defp merge(defaults, raw) when is_map(raw) do
    %__MODULE__{
      project: pick(raw, "project", defaults.project),
      test: pick(raw, "test", defaults.test),
      server: pick(raw, "server", defaults.server),
      browser: pick(raw, "browser", defaults.browser),
      editor: pick(raw, "editor", defaults.editor)
    }
  end

  defp pick(map, key, fallback) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _ -> fallback
    end
  end
end
