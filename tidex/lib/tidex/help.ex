defmodule Tidex.Help do
  @moduledoc false

  alias Tidex.Modal

  @column_width 24

  @spec modal() :: Modal.t()
  def modal do
    %Modal{
      kind: :help,
      title: "help",
      lines: [
        pair(key("t", "run tests"), key("s", "server sheet/start")),
        pair(key("f", "failure box"), key("x", "stop server")),
        pair(key("e", "edit failure"), key("b", "open browser")),
        pair(key("0", "edit tidex.conf"), "1-4  listed files"),
        pair(key("g", "git sheet"), "arrows  scroll server"),
        pair("left/right  failures", key("?", "close help"))
      ],
      commands: key("q", "quit") <> "   esc close",
      max_width: 50,
      max_height: 10
    }
  end

  defp key(letter, rest), do: Termex.bold(letter) <> "  " <> rest

  defp pair(left, right) do
    visible = left |> Termex.ANSI.strip() |> String.length()
    left <> String.duplicate(" ", max(@column_width - visible, 1)) <> right
  end
end
