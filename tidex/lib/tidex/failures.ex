defmodule Tidex.Failures do
  @moduledoc false

  @type t :: %{
          name: String.t(),
          file: String.t() | nil,
          line: pos_integer() | nil,
          source_file: String.t() | nil,
          source_line: pos_integer() | nil,
          snippet: String.t()
        }

  @exunit_header ~r/^\s+\d+\)\s+(.*\S)\s*$/
  @exunit_file_line ~r/(\S+\.exs):(\d+)/
  @elixir_source_line ~r/([^\s()]+\.ex):(\d+)/
  @minitest_header ~r/^\s+\d+\)\s+(Failure|Error):\s*$/
  @ruby_file_line ~r/([^\s\[]+\.rb):(\d+)/

  @spec showing?(map()) :: boolean()
  def showing?(%{test_state: :fail, failures: [_ | _]}), do: true
  def showing?(_), do: false

  @spec parse(
          [String.t()] | String.t(),
          :exunit | :minitest | :none,
          String.t() | nil
        ) :: [t()]
  def parse(text, format \\ :exunit, project_root \\ nil)

  def parse(text, format, project_root) when is_binary(text),
    do: parse(String.split(text, "\n"), format, project_root)

  def parse(lines, :exunit, project_root) when is_list(lines) do
    lines
    |> chunks(&exunit_header?/1)
    |> Enum.map(&parse_exunit_chunk(&1, project_root))
  end

  def parse(lines, :minitest, project_root) when is_list(lines) do
    lines
    |> chunks(&minitest_header?/1)
    |> Enum.map(&parse_minitest_chunk(&1, project_root))
  end

  def parse(lines, :none, _project_root) when is_list(lines), do: []

  @spec current(map()) :: t() | nil
  def current(%{failures: []}), do: nil

  def current(%{failures: failures, failure_index: index}) do
    Enum.at(failures, rem(index, length(failures)))
  end

  @spec cycle(map(), integer()) :: map()
  def cycle(%{failures: []} = state, _delta), do: state

  def cycle(%{failures: failures, failure_index: index} = state, delta) do
    n = length(failures)
    %{state | failure_index: Integer.mod(index + delta, n)}
  end

  @spec modal(map()) :: Tidex.Modal.t() | nil
  def modal(%{failures: []}), do: nil

  def modal(state) do
    fail = current(state)
    n = length(state.failures)
    i = rem(state.failure_index, n) + 1

    %Tidex.Modal{
      kind: :fail,
      title: "fail #{i}/#{n}",
      lines: body(fail),
      commands: commands(fail),
      min_width: 60,
      max_width: 60,
      min_height: 9,
      max_height: 9
    }
  end

  @exunit_module ~r/^(?<name>.*)\s+\((?<module>[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\)\s*$/

  defp body(fail) do
    {name, module} = split_module(fail.name || "")

    ([name, "reported: " <> location(fail, module)] ++
       source_line(fail) ++
       snippet_lines(fail.snippet))
    |> Enum.concat(["", "", "", ""])
    |> Enum.take(5)
  end

  defp commands(fail) do
    reported = Termex.bold("e") <> "  reported"
    output = Termex.bold("o") <> "  output"

    case Map.get(fail, :source_file) do
      source when is_binary(source) and source != "" ->
        reported <> "   " <> Termex.bold("s") <> "  source   " <> output <> "   esc"

      _ ->
        reported <> "   " <> output <> "   esc"
    end
  end

  defp source_line(fail) do
    case {Map.get(fail, :source_file), Map.get(fail, :source_line)} do
      {file, line} when is_binary(file) and is_integer(line) -> ["source:   #{file}:#{line}"]
      {file, _line} when is_binary(file) -> ["source:   #{file}"]
      _ -> []
    end
  end

  defp split_module(name) do
    case Regex.run(@exunit_module, name, capture: :all_but_first) do
      [name, module] when name != "" -> {name, module}
      _ -> {name, ""}
    end
  end

  defp location(fail, module) do
    case {module, place(fail)} do
      {"", place} -> place
      {module, ""} -> module
      {module, place} -> module <> " " <> place
    end
  end

  defp place(%{file: file, line: line}) when is_binary(file) and is_integer(line),
    do: "#{file}:#{line}"

  defp place(%{file: file}) when is_binary(file), do: file
  defp place(_), do: ""

  defp snippet_lines(text) when is_binary(text) do
    text
    |> String.split(" · ")
    |> Enum.take(2)
  end

  defp snippet_lines(_), do: []

  defp chunks(lines, header?) do
    {chunks, current} =
      Enum.reduce(lines, {[], []}, fn line, {chunks, current} ->
        if header?.(line) do
          {push(chunks, current, header?), [line]}
        else
          {chunks, current ++ [line]}
        end
      end)

    push(chunks, current, header?)
    |> Enum.reverse()
  end

  defp push(chunks, [], _header?), do: chunks

  defp push(chunks, [first | _] = current, header?) do
    if header?.(first), do: [current | chunks], else: chunks
  end

  defp exunit_header?(line), do: Regex.match?(@exunit_header, line)
  defp minitest_header?(line), do: Regex.match?(@minitest_header, line)

  defp parse_exunit_chunk([header | rest], project_root) do
    name =
      case Regex.run(@exunit_header, header) do
        [_, name] -> String.trim(name)
        _ -> String.trim(header)
      end

    {file, line} = file_line(rest, @exunit_file_line)

    {source_file, source_line} =
      rest |> after_stacktrace() |> source_file_line(@elixir_source_line, project_root)

    snippet = snippet(rest, @exunit_file_line)

    %{
      name: name,
      file: file,
      line: line,
      source_file: source_file,
      source_line: source_line,
      snippet: snippet
    }
  end

  defp parse_minitest_chunk([header | rest], project_root) do
    kind =
      case Regex.run(@minitest_header, header) do
        [_, kind] -> kind
        _ -> "Failure"
      end

    name_line = Enum.find(rest, "", &(String.trim(&1) != ""))

    name =
      name_line
      |> String.trim()
      |> String.replace(~r/\s+\[[^\]]+\.rb:\d+\]:?\s*$/, "")
      |> String.trim_trailing(":")
      |> case do
        "" -> kind
        name -> name
      end

    {file, line} = reported_file_line(rest, @ruby_file_line)
    {source_file, source_line} = source_file_line(rest, @ruby_file_line, project_root)
    snippet = minitest_snippet(rest, name_line)

    %{
      name: name,
      file: file,
      line: line,
      source_file: source_file,
      source_line: source_line,
      snippet: snippet
    }
  end

  defp after_stacktrace(lines) do
    case Enum.split_while(lines, &(String.trim(&1) != "stacktrace:")) do
      {_before, [_marker | stacktrace]} -> stacktrace
      _ -> []
    end
  end

  defp source_file_line(lines, pattern, project_root) do
    Enum.find_value(lines, {nil, nil}, fn line ->
      case Regex.run(pattern, line) do
        [_, file, number] ->
          if project_source?(file, project_root),
            do: {file, String.to_integer(number)},
            else: nil

        _ ->
          nil
      end
    end)
  end

  defp project_source?(file, project_root) do
    parts = file |> Path.split() |> Enum.reject(&(&1 in ["/", "."]))
    excluded? = test_path?(file) or Enum.any?(parts, &(&1 in ["deps", "_build"]))

    local? =
      case project_root do
        root when is_binary(root) ->
          root = Path.expand(root)

          path =
            if Path.type(file) == :absolute, do: Path.expand(file), else: Path.expand(file, root)

          path == root or String.starts_with?(path, root <> "/")

        _ ->
          Path.type(file) != :absolute and not String.starts_with?(file, "../")
      end

    local? and not excluded?
  end

  defp test_path?(file), do: Enum.any?(Path.split(file), &(&1 in ["test", "spec"]))

  defp file_line(lines, pattern) do
    Enum.find_value(lines, {nil, nil}, fn line ->
      case Regex.run(pattern, line) do
        [_, file, number] -> {file, String.to_integer(number)}
        _ -> nil
      end
    end)
  end

  defp reported_file_line(lines, pattern) do
    Enum.find_value(lines, fn line ->
      case Regex.run(pattern, line) do
        [_, file, number] ->
          if test_path?(file), do: {file, String.to_integer(number)}

        _ ->
          nil
      end
    end) || file_line(lines, pattern)
  end

  defp snippet(lines, file_line_pattern) do
    lines
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "stacktrace")))
    |> Enum.reject(&Regex.match?(file_line_pattern, &1))
    |> Enum.take(2)
    |> Enum.join(" · ")
  end

  defp minitest_snippet(lines, name_line) do
    lines
    |> Enum.reject(&(&1 == name_line))
    |> snippet(@ruby_file_line)
  end
end
