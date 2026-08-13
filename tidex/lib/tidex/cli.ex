defmodule Tidex.CLI do
  @moduledoc false

  def main(_args \\ []) do
    Tidex.App.start()
  end
end
