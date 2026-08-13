defmodule Tidex.CLI do
  @moduledoc false

  def main(_args \\ []) do
    Tidex.App.start(poll_git: true)
  end
end
