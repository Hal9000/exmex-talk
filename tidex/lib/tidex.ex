defmodule Tidex do
  @moduledoc """
  A language-agnostic development workbench built on Termex.

  Tidex owns the lobby, command sheets, git, browser, and editor. A
  supervisor owns the git poller and a `DynamicSupervisor` of jobs.
  Termex owns drawing, clipping, keys, and yielding the terminal.
  """

  @spec start(keyword()) :: :ok
  def start(opts \\ []) do
    Tidex.App.start(opts)
  end
end
