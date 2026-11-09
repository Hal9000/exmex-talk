defmodule Tidex.Diagnostics do
  @moduledoc false

  alias Tidex.Modal

  @type source :: :test | :server

  @type t :: %{
          file: String.t(),
          line: pos_integer(),
          column: pos_integer() | nil,
          message: String.t()
        }

  @colon_location ~r/(?<file>(?:[A-Za-z]:)?[^\s:]+):(?<line>\d+)(?::(?<column>\d+))?/
  @paren_location ~r/(?<file>[^( \n][^(\n]*?)\((?<line>\d+),(?<column>\d+)\)/
  @direct_error ~r/(?:\berror(?:\[[^\]]+\])?\b|fatal error|syntax error|\bundefined\b|cannot find|not found|undeclared|expected|invalid)/i
  @compile_header ~r/(?:\berror(?:\[[^\]]+\])?:?|SyntaxError|CompileError|TokenMissingError)/i
  @excluded_parts ~w(deps _build node_modules vendor)

  @spec parse([String.t()] | String.t(), String.t() | nil) :: [t()]
  def parse(text, project_root)

  def parse(text, project_root) when is_binary(text),
    do: parse(String.split(text, "\n"), project_root)

  def parse(lines, project_root) when is_list(lines) do
    root = Path.expand(project_root || ".")

    lines
    |> Enum.map(&Termex.ANSI.strip(to_string(&1)))
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, index}, diagnostics ->
      case diagnostic(line, preceding_error(lines, index), root) do
        nil -> diagnostics
        item -> [item | diagnostics]
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq_by(&{&1.file, &1.line, &1.column, &1.message})
  end

  @spec current(map(), source()) :: t() | nil
  def current(state, source) do
    items = Map.get(state.diagnostics, source, [])
    index = Map.get(state.diagnostic_indices, source, 0)
    if items == [], do: nil, else: Enum.at(items, rem(index, length(items)))
  end

  @spec cycle(map(), source(), integer()) :: map()
  def cycle(state, source, delta) do
    items = Map.get(state.diagnostics, source, [])

    if items == [] do
      state
    else
      index = Map.get(state.diagnostic_indices, source, 0)

      indices =
        Map.put(state.diagnostic_indices, source, Integer.mod(index + delta, length(items)))

      %{state | diagnostic_indices: indices}
    end
  end

  @spec modal(map(), source()) :: Modal.t() | nil
  def modal(state, source) do
    items = Map.get(state.diagnostics, source, [])

    if items == [] do
      nil
    else
      item = current(state, source)
      index = Map.get(state.diagnostic_indices, source, 0)
      location = format_location(item)

      %Modal{
        kind: :diagnostic,
        page: source,
        title: "compile error #{rem(index, length(items)) + 1}/#{length(items)}",
        lines: [item.message, "", "reported: #{location}"],
        commands:
          Termex.bold("e") <>
            "  edit   " <> Termex.bold("o") <> "  output   ←/→ error   esc",
        min_width: 60,
        max_width: 60,
        min_height: 9,
        max_height: 9
      }
    end
  end

  defp diagnostic(line, prior_error, root) do
    with {:ok, location, before, after_location} <- parse_location(line),
         true <- direct_error?(before, after_location) or is_binary(prior_error),
         {:ok, file} <- project_file(location.file, root) do
      %{
        file: file,
        line: location.line,
        column: location.column,
        message: message(before, after_location, prior_error)
      }
    else
      _ -> nil
    end
  end

  defp parse_location(line) do
    case named_location(@colon_location, line) || named_location(@paren_location, line) do
      nil ->
        :error

      captures ->
        file = captures["file"] |> String.trim() |> String.trim_leading("-->") |> String.trim()
        before = String.slice(line, 0, captures.first) || ""
        after_location = String.slice(line, captures.last, String.length(line)) || ""

        {:ok,
         %{
           file: file,
           line: String.to_integer(captures["line"]),
           column: integer(captures["column"])
         }, before, after_location}
    end
  end

  defp named_location(regex, line) do
    case Regex.run(regex, line, return: :index) do
      nil ->
        nil

      indices ->
        names = Regex.names(regex)
        values = Regex.run(regex, line, capture: names)
        captures = names |> Enum.zip(values) |> Map.new()
        {first, length} = hd(indices)
        Map.merge(captures, %{first: first, last: first + length})
    end
  end

  defp preceding_error(lines, index) do
    lines
    |> Enum.slice(max(index - 3, 0), min(index, 3))
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      line = Termex.ANSI.strip(to_string(line))

      if Regex.match?(@compile_header, line) and parse_location(line) == :error,
        do: String.trim(line)
    end)
  end

  defp direct_error?(before, after_location),
    do: Regex.match?(@compile_header, before) or Regex.match?(@direct_error, after_location)

  defp project_file(file, root) do
    expanded =
      if Path.type(file) == :absolute, do: Path.expand(file), else: Path.expand(file, root)

    parts = Path.split(Path.relative_to(expanded, root))

    cond do
      expanded != root and not String.starts_with?(expanded, root <> "/") -> :error
      Enum.any?(parts, &(&1 in @excluded_parts)) -> :error
      not File.regular?(expanded) -> :error
      true -> {:ok, Path.relative_to(expanded, root)}
    end
  end

  defp message(before, after_location, prior_error) do
    after_location
    |> String.trim()
    |> String.trim_leading(":")
    |> String.trim()
    |> case do
      "" -> String.trim(prior_error || before)
      text -> text
    end
  end

  defp format_location(item) do
    "#{item.file}:#{item.line}" <>
      if(is_integer(item.column), do: ":#{item.column}", else: "")
  end

  defp integer(nil), do: nil
  defp integer(""), do: nil
  defp integer(value), do: String.to_integer(value)
end
