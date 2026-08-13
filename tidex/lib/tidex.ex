defmodule Tidex do
  @moduledoc """
  A language-agnostic development workbench built on Termex.

  Tidex owns the dashboard, test command, and server process. Termex
  owns drawing, clipping, and key input.
  """

  @spec start(keyword()) :: :ok
  def start(opts \\ []) do
    Tidex.App.start(opts)
  end
end
