defmodule Mix.Tasks.Tidex do
  use Mix.Task

  @shortdoc "Start the Tidex development workbench"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Tidex.CLI.main([])
  end
end
