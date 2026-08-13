defmodule Tidex do
  @moduledoc """
  A language-agnostic development workbench built on Termex.

  Tidex owns the dashboard and the commands. Termex owns drawing and
  key input. External commands run through a small injectable runner so
  the `t` key can be tested without depending on a particular shell.
  """

  @spec start(keyword()) :: :ok
  def start(opts \\ []) do
    Tidex.App.start(opts)
  end
end
