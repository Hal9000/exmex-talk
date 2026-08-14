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
end
