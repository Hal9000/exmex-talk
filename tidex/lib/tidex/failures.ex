defmodule Tidex.Failures do
  @moduledoc false

  @type t :: %{
          name: String.t(),
          file: String.t() | nil,
          line: pos_integer() | nil,
          snippet: String.t()
        }

  @exunit_header ~r/^\s+\d+\)\s+(.*\S)\s*$/
  @exunit_file_line ~r/(\S+\.exs):(\d+)/
  @minitest_header ~r/^\s+\d+\)\s+(Failure|Error):\s*$/
  @ruby_file_line ~r/([^\s\[]+\.rb):(\d+)/

  @spec showing?(map()) :: boolean()
  def showing?(%{test_state: :fail, failures: [_ | _]}), do: true
  def showing?(_), do: false

  @spec parse([String.t()] | String.t(), :exunit | :minitest | :none) :: [t()]
  def parse(text, format \\ :exunit)

  def parse(text, format) when is_binary(text), do: parse(String.split(text, "\n"), format)

  def parse(lines, :exunit) when is_list(lines) do
    lines
    |> chunks(&exunit_header?/1)
    |> Enum.map(&parse_exunit_chunk/1)
  end

  def parse(lines, :minitest) when is_list(lines) do
    lines
    |> chunks(&minitest_header?/1)
    |> Enum.map(&parse_minitest_chunk/1)
  end

  def parse(lines, :none) when is_list(lines), do: []

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
      commands: Termex.bold("e") <> "  edit  left/right  esc",
      min_width: 60,
      max_width: 60,
      min_height: 8,
      max_height: 8
    }
  end

  defp body(fail) do
    [fail.name || "", location(fail) | snippet_lines(fail.snippet)]
    |> Enum.concat(["", "", "", ""])
    |> Enum.take(4)
  end

  defp location(%{file: file, line: line}) when is_binary(file) and is_integer(line),
    do: "#{file}:#{line}"

  defp location(%{file: file}) when is_binary(file), do: file
  defp location(_), do: ""

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

  defp parse_exunit_chunk([header | rest]) do
    name =
      case Regex.run(@exunit_header, header) do
        [_, name] -> String.trim(name)
        _ -> String.trim(header)
      end

    {file, line} = file_line(rest, @exunit_file_line)
    snippet = snippet(rest, @exunit_file_line)

    %{name: name, file: file, line: line, snippet: snippet}
  end

  defp parse_minitest_chunk([header | rest]) do
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

    {file, line} = file_line(rest, @ruby_file_line)
    snippet = minitest_snippet(rest, name_line)

    %{name: name, file: file, line: line, snippet: snippet}
  end

  defp file_line(lines, pattern) do
    Enum.find_value(lines, {nil, nil}, fn line ->
      case Regex.run(pattern, line) do
        [_, file, number] -> {file, String.to_integer(number)}
        _ -> nil
      end
    end)
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
