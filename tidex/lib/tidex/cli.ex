defmodule Tidex.CLI do
  @moduledoc false

  def main(_args \\ []) do
    {:ok, _} = Application.ensure_all_started(:tidex)
    Tidex.UI.run(poll_git: true, name: Tidex.UI)
  end
end
