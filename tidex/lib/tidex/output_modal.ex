defmodule Tidex.OutputModal do
  @moduledoc false

  alias Tidex.{Modal, Scroll}

  @type source :: :test | :server

  @spec modal(source(), [String.t()], Scroll.t()) :: Modal.t()
  def modal(source, lines, scroll \\ :follow) when source in [:test, :server] do
    %Modal{
      kind: :output,
      page: source,
      title: title(source),
      lines: if(lines == [], do: ["(no output)"], else: lines),
      commands: "↑/↓ pgup/pgdn scroll   esc close",
      scroll: scroll,
      min_width: 60,
      max_width: 72,
      min_height: 10,
      max_height: 16
    }
  end

  @spec scroll(Modal.t(), term(), %{width: pos_integer(), height: pos_integer()}) :: Modal.t()
  def scroll(%Modal{kind: :output} = modal, key, screen) do
    body_height = Modal.body_height(screen, modal)

    delta =
      case key do
        :up -> -1
        :down -> 1
        :page_up -> -max(body_height, 1)
        :page_down -> max(body_height, 1)
      end

    %{modal | scroll: Scroll.step(modal.lines, body_height, modal.scroll, delta)}
  end

  defp title(:test), do: "test failure output"
  defp title(:server), do: "server output"
end
