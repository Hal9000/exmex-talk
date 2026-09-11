defmodule Mix.Tasks.Tidex do
  use Mix.Task

  @shortdoc "Start the Tidex development workbench"

  @example Path.expand("../../../../examples/proj1", __DIR__)

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Tidex.CLI.main(default_args(args))
  end

  @doc false
  def default_args([]) do
    if File.exists?(Path.join(@example, "tidex.conf")) do
      [@example]
    else
      []
    end
  end

  def default_args(args), do: args
end
