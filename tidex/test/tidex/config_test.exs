defmodule Tidex.ConfigTest do
  use ExUnit.Case, async: true

  alias Tidex.Config

  setup do
    dir = Path.join(System.tmp_dir!(), "tidex-config-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "defaults when no tidex.conf is found", %{dir: dir} do
    config = Config.load(dir)
    assert config.project == Path.basename(dir)
    assert config.server == "python3 -m http.server 4000"
    assert config.browser == "http://localhost:4000"
    assert is_binary(config.editor)
  end

  test "loads keys from tidex.conf and walks parents", %{dir: dir} do
    File.write!(Path.join(dir, "tidex.conf"), """
    project: demo
    test: echo configured
    server: echo serve
    browser: http://example.test
    editor: true
    """)

    nested = Path.join(dir, "nested")
    File.mkdir_p!(nested)

    config = Config.load(nested)
    assert config.project == "demo"
    assert config.test == "echo configured"
    assert config.server == "echo serve"
    assert config.browser == "http://example.test"
    assert config.editor == "true"
    assert config.files == %{}
  end

  test "loads file1-file4 and skips missing slots", %{dir: dir} do
    File.write!(Path.join(dir, "tidex.conf"), """
    project: demo
    file1: README.md
    file3: lib/tidex.ex
    file4:
    """)

    config = Config.load(dir)
    assert config.files == %{1 => "README.md", 3 => "lib/tidex.ex"}
  end

  test "project defaults to the config directory name", %{dir: dir} do
    File.write!(Path.join(dir, "tidex.conf"), """
    test: echo from-root
    """)

    nested = Path.join(dir, "nested")
    File.mkdir_p!(nested)

    config = Config.load(nested)
    assert config.project == Path.basename(dir)
    assert config.test == "echo from-root"
  end

  test "parses comments, blanks, quotes, and URLs" do
    parsed =
      Config.parse("""
      # a comment

      project: "quoted name"
      browser: http://localhost:4000
      unknown: ignored
      editor:
      """)

    assert parsed == %{
             "project" => "quoted name",
             "browser" => "http://localhost:4000"
           }
  end

  test "refuses to write in home, /, and /tmp", %{dir: dir} do
    assert Config.blocked?("/")
    assert Config.blocked?("/tmp")
    assert Config.blocked?(System.user_home())
    refute Config.blocked?(dir)
    assert {:error, :blocked} = Config.write!("/")
    assert {:error, :blocked} = Config.write!("/tmp")
  end

  test "write! dumps guessed defaults and omits editor", %{dir: dir} do
    File.write!(Path.join(dir, "mix.exs"), "")
    assert {:ok, path} = Config.write!(dir)
    assert path == Path.join(dir, "tidex.conf")
    body = File.read!(path)
    assert body =~ "project: #{Path.basename(dir)}"
    assert body =~ "test: mix test"
    assert body =~ "server: python3 -m http.server 4000"
    refute body =~ ~r/^editor:/m
    assert body =~ ~r/^file1: mix.exs$/m
    refute body =~ ~r/^file2:/m
  end

  test "write! lists README.md before mix.exs when both exist", %{dir: dir} do
    File.write!(Path.join(dir, "README.md"), "hi\n")
    File.write!(Path.join(dir, "mix.exs"), "")
    assert {:ok, path} = Config.write!(dir)
    body = File.read!(path)
    assert body =~ ~r/^file1: README.md$/m
    assert body =~ ~r/^file2: mix.exs$/m
  end

  test "git_root is the upward toplevel", %{dir: dir} do
    git!(dir, ["init", "-b", "main"])
    nested = Path.join(dir, "nested")
    File.mkdir_p!(nested)
    assert Config.git_root(nested) == Path.expand(dir)
    assert Config.git_root(dir) == Path.expand(dir)
  end

  defp git!(dir, args) do
    {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
  end
end
