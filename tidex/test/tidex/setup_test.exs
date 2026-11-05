defmodule Tidex.SetupTest do
  use ExUnit.Case, async: true

  alias Tidex.Setup

  test "probe offers cwd and not git when there is no repo" do
    dir = tmp_dir()

    try do
      setup = Setup.probe(dir)
      assert setup.offer_cwd
      refute setup.offer_git
      refute setup.blocked
      assert setup.cwd == Path.expand(dir)
    after
      File.rm_rf!(dir)
    end
  end

  test "probe offers a different upward git root" do
    dir = tmp_dir()
    nested = Path.join(dir, "nested")
    File.mkdir_p!(nested)

    try do
      git!(dir, ["init", "-b", "main"])
      setup = Setup.probe(nested)
      assert setup.offer_cwd
      assert setup.offer_git
      assert setup.git_root == Path.expand(dir)
    after
      File.rm_rf!(dir)
    end
  end

  test "probe blocks home and does not offer a write" do
    setup = Setup.probe(System.user_home())
    assert setup.blocked
    refute setup.offer_cwd
    lines = Setup.lines(setup) |> Enum.map(&Termex.ANSI.strip/1)
    assert Enum.any?(lines, &(&1 == "cwd is not permitted"))
    assert Enum.any?(lines, &String.contains?(&1, "$HOME"))
    refute Setup.modal(setup).commands |> Termex.ANSI.strip() |> String.contains?("y ")
  end

  test "blocked cwd with a git root offers g but not y" do
    setup = %Setup{
      cwd: "/tmp",
      git_root: "/tmp/repo",
      blocked: true,
      offer_cwd: false,
      offer_git: true
    }

    lines = Setup.lines(setup) |> Enum.map(&Termex.ANSI.strip/1)
    assert Enum.any?(lines, &(&1 == "cwd is not permitted"))
    commands = Setup.modal(setup).commands |> Termex.ANSI.strip()
    assert commands =~ "g git root"
    refute commands =~ "y "
  end

  test "lines lead with git root when cwd has no project markers" do
    setup = %Setup{
      cwd: "/tmp/nested",
      git_root: "/tmp/repo",
      offer_cwd: true,
      offer_git: true
    }

    lines = Setup.lines(setup) |> Enum.map(&Termex.ANSI.strip/1)
    assert Enum.at(lines, 2) =~ "doesn't look like a project"
    assert Setup.modal(setup).commands |> Termex.ANSI.strip() |> String.contains?("g git root")
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tidex-setup-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp git!(dir, args) do
    {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
  end
end
