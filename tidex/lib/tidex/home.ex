defmodule Tidex.Home do
  @moduledoc """
  User defaults in `~/.tidex/tidex.conf`.

  This file is not on the walk toward `/`. A project `tidex.conf`
  wins per key. `editor` is the fallback when a project omits it.
  Other lines are a catalog of `dir: name`.
  """

  defstruct editor: nil, catalog: %{}

  @type t :: %__MODULE__{
          editor: String.t() | nil,
          catalog: %{optional(String.t()) => String.t()}
        }

  @filename "tidex.conf"

  @spec dir(keyword()) :: String.t() | nil
  def dir(opts \\ []) do
    Keyword.get(opts, :home) ||
      Application.get_env(:tidex, :home) ||
      default_dir()
  end

  @spec default_dir() :: String.t() | nil
  def default_dir do
    case System.user_home() do
      home when is_binary(home) -> Path.join(Path.expand(home), ".tidex")
      _ -> nil
    end
  end

  @spec file(keyword()) :: String.t() | nil
  def file(opts \\ []) do
    case dir(opts) do
      path when is_binary(path) -> Path.join(path, @filename)
      _ -> nil
    end
  end

  @spec load(keyword()) :: t()
  def load(opts \\ []) do
    case file(opts) do
      path when is_binary(path) ->
        if File.exists?(path), do: parse(File.read!(path)), else: %__MODULE__{}

      _ ->
        %__MODULE__{}
    end
  end

  @spec remember(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def remember(dir, name, opts \\ []) when is_binary(dir) and is_binary(name) do
    user = load(opts)
    catalog = Map.put(user.catalog, Path.expand(dir), name)
    write!(%{user | catalog: catalog}, opts)
  end

  @spec write!(t(), keyword()) :: :ok | {:error, term()}
  def write!(%__MODULE__{} = user, opts \\ []) do
    case dir(opts) do
      path when is_binary(path) ->
        File.mkdir_p!(path)
        File.write!(file(opts), dump(user))
        :ok

      _ ->
        {:error, :no_home}
    end
  end

  @spec lookup(t(), String.t()) :: String.t() | nil
  def lookup(%__MODULE__{catalog: catalog}, dir) do
    Map.get(catalog, Path.expand(dir))
  end

  @spec parse(String.t()) :: t()
  def parse(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.reduce(%__MODULE__{}, &parse_line/2)
  end

  @spec dump(t()) :: String.t()
  def dump(%__MODULE__{} = user) do
    """
    # Tidex user config (key: value)
    # editor is the fallback when a project omits it
    #{dump_editor(user.editor)}
    # catalog (dir: name)
    #{dump_catalog(user.catalog)}
    """
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
            put_entry(acc, key, value)

          _ ->
            acc
        end
    end
  end

  defp put_entry(acc, _key, ""), do: acc

  defp put_entry(acc, "editor", value), do: %{acc | editor: value}

  defp put_entry(acc, key, value) do
    if catalog_key?(key) do
      %{acc | catalog: Map.put(acc.catalog, Path.expand(key), value)}
    else
      acc
    end
  end

  defp catalog_key?(key) do
    String.starts_with?(key, "/") or String.starts_with?(key, "~")
  end

  defp dump_editor(nil), do: ""
  defp dump_editor(""), do: ""
  defp dump_editor(editor), do: "editor: #{editor}\n"

  defp dump_catalog(catalog) when catalog == %{}, do: ""

  defp dump_catalog(catalog) do
    catalog
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join("", fn {dir, name} -> "#{dir}: #{name}\n" end)
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
end
