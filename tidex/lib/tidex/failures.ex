defmodule Tidex.Failures do
  @moduledoc false

  @type t :: %{
          name: String.t(),
          file: String.t() | nil,
          line: pos_integer() | nil,
          snippet: String.t()
        }

  @header ~r/^\s+\d+\)\s+(.*)$/
  @file_line ~r/(\S+\.exs):(\d+)/

  @spec showing?(map()) :: boolean()
  def showing?(%{test_state: :fail, failures: [_ | _]}), do: true
  def showing?(_), do: false

  @spec parse([String.t()] | String.t()) :: [t()]
  def parse(text) when is_binary(text), do: parse(String.split(text, "\n"))

  def parse(lines) when is_list(lines) do
    lines
    |> chunk()
    |> Enum.map(&parse_chunk/1)
  end

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

  defp chunk(lines) do
    {chunks, current} =
      Enum.reduce(lines, {[], []}, fn line, {chunks, current} ->
        if header?(line) do
          {push(chunks, current), [line]}
        else
          {chunks, current ++ [line]}
        end
      end)

    push(chunks, current)
    |> Enum.reverse()
  end

  defp push(chunks, []), do: chunks

  defp push(chunks, [first | _] = current) do
    if header?(first), do: [current | chunks], else: chunks
  end

  defp header?(line), do: Regex.match?(@header, line)

  defp parse_chunk([header | rest]) do
    name =
      case Regex.run(@header, header) do
        [_, name] -> String.trim(name)
        _ -> String.trim(header)
      end

    {file, line} = file_line(rest)
    snippet = snippet(rest)

    %{name: name, file: file, line: line, snippet: snippet}
  end

  defp file_line(lines) do
    Enum.find_value(lines, {nil, nil}, fn line ->
      case Regex.run(@file_line, line) do
        [_, file, number] -> {file, String.to_integer(number)}
        _ -> nil
      end
    end)
  end

  defp snippet(lines) do
    lines
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "stacktrace")))
    |> Enum.reject(&Regex.match?(@file_line, &1))
    |> Enum.take(2)
    |> Enum.join(" · ")
  end
end
