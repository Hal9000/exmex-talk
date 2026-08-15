defmodule Tidex.Config do
  @moduledoc """
  Project label and commands from `tidex.conf`, walking from cwd toward `/`.

  Lines are `key: value`. `#` comments and blank lines are ignored.
  Known keys: `project`, `test`, `server`, `browser`, `editor`,
  and optional `file1`–`file4`. Missing file keys are omitted.

  When no file is found, Tidex can write one after a prompt. It refuses
  `$HOME`, `/`, and `/tmp`.
  """

  @filename "tidex.conf"
  @keys ~w(project test server browser editor file1 file2 file3 file4)
  @file_keys %{"file1" => 1, "file2" => 2, "file3" => 3, "file4" => 4}
  @detect ~w(README.md mix.exs package.json Cargo.toml go.mod)
  @blocked_exact ~w(/ /tmp /var /private/tmp /private/var)

  defstruct project: "tidex",
            test: "mix test",
            server: "python3 -m http.server 4000",
            browser: "http://localhost:4000",
            editor: "vi",
            files: %{}

  @type t :: %__MODULE__{
          project: String.t(),
          test: String.t(),
          server: String.t(),
          browser: String.t(),
          editor: String.t(),
          files: %{optional(1..4) => String.t()}
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

  @spec filename() :: String.t()
  def filename, do: @filename

  @spec blocked?(String.t()) :: boolean()
  def blocked?(dir) do
    dir = Path.expand(dir)
    home = home_dir()
    dir == home or dir in @blocked_exact
  end

  @spec project_markers?(String.t()) :: boolean()
  def project_markers?(dir) do
    dir = Path.expand(dir)

    Enum.any?(~w(mix.exs package.json Cargo.toml go.mod .git), fn name ->
      File.exists?(Path.join(dir, name))
    end)
  end

  @spec git_root(String.t()) :: String.t() | nil
  def git_root(cwd \\ File.cwd!()) do
    case System.cmd("git", ["rev-parse", "--show-toplevel"],
           cd: Path.expand(cwd),
           stderr_to_stdout: true,
           env: [{"LC_ALL", "C"}]
         ) do
      {out, 0} -> out |> String.trim() |> Path.expand()
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @spec write!(String.t()) :: {:ok, String.t()} | {:error, :blocked}
  def write!(dir) do
    dir = Path.expand(dir)

    if blocked?(dir) do
      {:error, :blocked}
    else
      File.mkdir_p!(dir)
      path = Path.join(dir, @filename)
      File.write!(path, dump(with_detected_files(defaults(dir), dir)))
      {:ok, path}
    end
  end

  @spec dump(t()) :: String.t()
  def dump(%__MODULE__{} = config) do
    """
    # Tidex project config (key: value)
    project: #{config.project}
    test: #{config.test}
    server: #{config.server}
    browser: #{config.browser}
    # editor falls back to $VISUAL / $EDITOR / vi
    """ <> dump_files(config.files)
  end

  defp dump_files(files) when files == %{}, do: ""

  defp dump_files(files) do
    1..4
    |> Enum.filter(&Map.has_key?(files, &1))
    |> Enum.map_join("", fn n -> "file#{n}: #{files[n]}\n" end)
  end

  defp with_detected_files(config, dir) do
    %{config | files: detect_files(dir)}
  end

  defp detect_files(dir) do
    @detect
    |> Enum.filter(&File.exists?(Path.join(dir, &1)))
    |> Enum.take(4)
    |> Enum.with_index(1)
    |> Map.new(fn {name, n} -> {n, name} end)
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
      editor: pick(raw, "editor", defaults.editor),
      files: parse_files(raw)
    }
  end

  defp parse_files(raw) do
    for {name, n} <- @file_keys,
        value = Map.get(raw, name),
        is_binary(value) and value != "",
        into: %{} do
      {n, value}
    end
  end

  defp pick(map, key, fallback) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _ -> fallback
    end
  end

  defp home_dir do
    case System.user_home() do
      home when is_binary(home) -> Path.expand(home)
      _ -> nil
    end
  end
end
