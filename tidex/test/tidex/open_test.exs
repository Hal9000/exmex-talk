defmodule Tidex.OpenTest do
  use ExUnit.Case, async: true

  alias Tidex.Open

  test "editor command true returns after the process exits" do
    assert :ok = Open.editor("true")
  end

  test "bare vim-family names jump to a line" do
    assert Open.editor_command("nvim", file: "test/foo_test.exs", line: 12) ==
             "nvim +12 'test/foo_test.exs'"

    assert Open.editor_command("vi", file: "lib/tidex.ex", line: 4) == "vi +4 'lib/tidex.ex'"
    assert Open.editor_command("emacs", file: "a.ex", line: 9) == "emacs +9 'a.ex'"
  end

  test "code and hx use path:line" do
    assert Open.editor_command("code", file: "test/foo_test.exs", line: 12) ==
             "code -g 'test/foo_test.exs:12'"

    assert Open.editor_command("hx", file: "test/foo_test.exs", line: 12) ==
             "hx 'test/foo_test.exs:12'"
  end

  test "a template interpolates file and line" do
    assert Open.editor_command("vim +{line} {file}", file: "x.exs", line: 3) ==
             "vim +3 'x.exs'"
  end

  test "without a line the jump is dropped" do
    assert Open.editor_command("nvim", file: "x.exs") == "nvim 'x.exs'"

    assert Open.editor_command("vim +{line} {file}", file: "x.exs") == "vim 'x.exs'"
  end

  test "unknown editors get the file appended" do
    assert Open.editor_command("nano", file: "x.exs", line: 3) == "nano 'x.exs'"
  end

  test "without a file the configured command is unchanged" do
    assert Open.editor_command("true", line: 12) == "true"
    assert Open.editor_command("nvim") == "nvim"
  end

  test "a command with extra flags is not rewritten" do
    assert Open.editor_command("vim -u NORC", file: "x.exs", line: 3) == "vim -u NORC 'x.exs'"
  end
end
