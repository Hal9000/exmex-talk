defmodule Mix.Tasks.Tidex do
  use Mix.Task

  @shortdoc "Start the Tidex development workbench"

  @example Path.expand("../../../examples/proj1", __DIR__)

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Tidex.CLI.main(with_default(args))
  end

  defp with_default([]) do
    if File.exists?(Path.join(@example, "tidex.conf")) do
      [@example]
    else
      []
    end
  end

  defp with_default(args), do: args
end
