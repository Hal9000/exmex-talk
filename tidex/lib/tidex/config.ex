defmodule Tidex.Config do
  @moduledoc """
  Project commands loaded from `tidex.exs`, walking from cwd toward `/`.
  """

  defstruct test: "mix test",
            server: "python3 -m http.server 4000",
            browser: "http://localhost:4000",
            editor: "vi"

  @type t :: %__MODULE__{
          test: String.t(),
          server: String.t(),
          browser: String.t(),
          editor: String.t()
        }

  @spec load(String.t()) :: t()
  def load(cwd \\ File.cwd!()) do
    case find_file(cwd) do
      nil -> defaults(cwd)
      path -> merge(defaults(cwd), eval(path))
    end
  end

  @spec defaults(String.t()) :: t()
  def defaults(cwd \\ File.cwd!()) do
    %__MODULE__{
      test: default_test_command(cwd),
      server: "python3 -m http.server 4000",
      browser: "http://localhost:4000",
      editor: default_editor()
    }
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
    path = Path.join(dir, "tidex.exs")

    cond do
      File.exists?(path) ->
        path

      true ->
        parent = Path.dirname(dir)
        if parent == dir, do: nil, else: find_file(parent)
    end
  end

  defp eval(path) do
    {result, _binding} = Code.eval_file(path)
    result
  end

  defp merge(defaults, raw) when is_map(raw) do
    %__MODULE__{
      test: pick(raw, :test, defaults.test),
      server: pick(raw, :server, defaults.server),
      browser: pick(raw, :browser, defaults.browser),
      editor: pick(raw, :editor, defaults.editor)
    }
  end

  defp merge(defaults, _other), do: defaults

  defp pick(map, key, fallback) do
    case Map.get(map, key, Map.get(map, Atom.to_string(key))) do
      value when is_binary(value) and value != "" -> value
      _ -> fallback
    end
  end
end
