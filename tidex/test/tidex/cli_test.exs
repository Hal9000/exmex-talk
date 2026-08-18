defmodule Tidex.CLITest do
  use ExUnit.Case, async: true

  test "project_dir is cwd when there are no args" do
    assert Tidex.CLI.project_dir([]) == File.cwd!()
  end

  test "project_dir expands a path argument" do
    assert Tidex.CLI.project_dir(["/tmp"]) == "/tmp"
    assert Tidex.CLI.project_dir(["."]) == File.cwd!()
  end
end
