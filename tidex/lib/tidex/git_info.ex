defmodule Tidex.GitInfo do
  @moduledoc false

  alias Tidex.Modal

  @spec modal() :: Modal.t()
  def modal do
    %Modal{
      kind: :stub,
      title: "git info",
      lines: ["Not implemented yet."],
      commands: "esc close",
      max_width: 40,
      max_height: 6,
      min_width: 28,
      min_height: 5
    }
  end
end
