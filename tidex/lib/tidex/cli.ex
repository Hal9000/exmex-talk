defmodule Tidex.CLI do
  @moduledoc false

  def main(args \\ []) do
    {:ok, _} = Application.ensure_all_started(:tidex)
    Tidex.UI.run(poll_git: true, name: Tidex.UI, cwd: project_dir(args))
  end

  @doc false
  def project_dir([]), do: File.cwd!()
  def project_dir([path | _]), do: Path.expand(path)
end
