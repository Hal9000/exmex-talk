defmodule Tidex.CLITest do
  use ExUnit.Case, async: true

  test "project_dir is cwd when there are no args" do
    assert Tidex.CLI.project_dir([]) == File.cwd!()
  end

  test "project_dir expands a path argument" do
    assert Tidex.CLI.project_dir(["/tmp"]) == "/tmp"
    assert Tidex.CLI.project_dir(["."]) == File.cwd!()
  end

  test "mix tidex defaults to the example project" do
    [path] = Mix.Tasks.Tidex.default_args([])
    assert Path.basename(path) == "proj1"
    assert File.exists?(Path.join(path, "tidex.conf"))
  end
end
