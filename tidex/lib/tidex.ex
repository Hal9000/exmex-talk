defmodule Tidex do
  @moduledoc """
  A language-agnostic development workbench built on Termex.

  Tidex owns the dashboard, commands, git, browser, and editor. Termex
  owns drawing, clipping, keys, and yielding the terminal.
  """

  @spec start(keyword()) :: :ok
  def start(opts \\ []) do
    Tidex.App.start(opts)
  end
end
