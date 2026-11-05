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
    home = Path.join(dir, "user")
    config = Config.load(dir, home: home)
    assert config.project == Path.basename(dir)
    assert config.server == nil
    assert config.browser == nil
    assert is_binary(config.editor)
  end

  test "loads keys from tidex.conf and walks parents", %{dir: dir} do
    File.write!(Path.join(dir, "tidex.conf"), """
    project: demo
    test: echo configured
    test_format: minitest
    server: echo serve
    browser: http://example.test
    editor: true
    """)

    nested = Path.join(dir, "nested")
    File.mkdir_p!(nested)

    config = Config.load(nested, home: Path.join(dir, "user"))
    assert config.project == "demo"
    assert config.test == "echo configured"
    assert config.test_format == :minitest
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

    config = Config.load(dir, home: Path.join(dir, "user"))
    assert config.files == %{1 => "README.md", 3 => "lib/tidex.ex"}
  end

  test "project defaults to the config directory name", %{dir: dir} do
    File.write!(Path.join(dir, "tidex.conf"), """
    test: echo from-root
    """)

    nested = Path.join(dir, "nested")
    File.mkdir_p!(nested)

    config = Config.load(nested, home: Path.join(dir, "user"))
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
    home = Path.join(dir, "user")
    assert {:ok, path} = Config.write!(dir, home: home)
    assert path == Path.join(dir, "tidex.conf")
    body = File.read!(path)
    assert body =~ "project: #{Path.basename(dir)}"
    assert body =~ "test: mix test"
    assert body =~ "test_format: exunit"
    refute body =~ ~r/^server:/m
    refute body =~ ~r/^browser:/m
    refute body =~ ~r/^editor:/m
    assert body =~ ~r/^file1: mix.exs$/m
    refute body =~ ~r/^file2:/m
  end

  test "write! lists README.md before mix.exs when both exist", %{dir: dir} do
    File.write!(Path.join(dir, "README.md"), "hi\n")
    File.write!(Path.join(dir, "mix.exs"), "")
    home = Path.join(dir, "user")
    assert {:ok, path} = Config.write!(dir, home: home)
    body = File.read!(path)
    assert body =~ ~r/^file1: README.md$/m
    assert body =~ ~r/^file2: mix.exs$/m
  end

  test "Ruby markers select a Minitest command and parser", %{dir: dir} do
    File.write!(Path.join(dir, ".ruby-version"), "3.3\n")

    config = Config.defaults(dir)

    assert config.test =~ "ruby -Itest"
    assert config.test =~ "test/**/*_test.rb"
    assert config.test =~ "require File.expand_path(f)"
    assert config.test_format == :minitest
    assert Config.project_markers?(dir)
  end

  test "Ruby markers take precedence over a frontend package.json", %{dir: dir} do
    File.write!(Path.join(dir, "Gemfile"), "")
    File.write!(Path.join(dir, "package.json"), "{}")

    config = Config.defaults(dir)

    assert config.test =~ "ruby -Itest"
    assert config.test_format == :minitest
  end

  test "user editor is used when the project omits editor", %{dir: dir} do
    home = Path.join(dir, "user")
    File.mkdir_p!(home)
    File.write!(Path.join(home, "tidex.conf"), "editor: hx\n")
    File.write!(Path.join(dir, "tidex.conf"), "project: demo\n")

    config = Config.load(dir, home: home)
    assert config.editor == "hx"
    assert config.project == "demo"
  end

  test "project tidex.conf wins editor over ~/.tidex", %{dir: dir} do
    home = Path.join(dir, "user")
    File.mkdir_p!(home)
    File.write!(Path.join(home, "tidex.conf"), "editor: hx\n")
    File.write!(Path.join(dir, "tidex.conf"), "editor: nvim\n")

    config = Config.load(dir, home: home)
    assert config.editor == "nvim"
  end

  test "catalog name is used when the project omits project", %{dir: dir} do
    home = Path.join(dir, "user")
    File.mkdir_p!(home)

    File.write!(Path.join(home, "tidex.conf"), """
    #{Path.expand(dir)}: catalog-name
    """)

    File.write!(Path.join(dir, "tidex.conf"), "test: echo from-root\n")
    config = Config.load(dir, home: home)
    assert config.project == "catalog-name"
    assert config.test == "echo from-root"
  end

  test "walk skips $HOME and ~/.tidex tidex.conf files", %{dir: dir} do
    fake_home = Path.join(dir, "home")
    user = Path.join(fake_home, ".tidex")
    project = Path.join(fake_home, "src/app")
    File.mkdir_p!(user)
    File.mkdir_p!(project)
    File.write!(Path.join(fake_home, "tidex.conf"), "project: from-home\neditor: vi\n")
    File.write!(Path.join(user, "tidex.conf"), "editor: hx\nproject: from-user\n")

    assert Config.find_file(project, home: user) == nil
    config = Config.load(project, home: user)
    assert config.project == "app"
    assert config.editor == "hx"
  end

  test "write! records the directory in the user catalog", %{dir: dir} do
    home = Path.join(dir, "user")
    File.write!(Path.join(dir, "mix.exs"), "")
    assert {:ok, _} = Config.write!(dir, home: home)
    user = Tidex.Home.load(home: home)
    assert Tidex.Home.lookup(user, dir) == Path.basename(dir)
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
