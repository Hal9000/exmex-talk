defmodule Tidex.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias Tidex.Diagnostics

  setup do
    root = Path.join(System.tmp_dir!(), "tidex-diagnostics-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "src"))
    File.mkdir_p!(Path.join(root, "web"))
    File.write!(Path.join(root, "lib/demo.ex"), "defmodule Demo do\nend\n")
    File.write!(Path.join(root, "src/main.rs"), "fn main() {}\n")
    File.write!(Path.join(root, "web/app.ts"), "const answer = missing;\n")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "parses common compiler diagnostics with project-local locations", %{root: root} do
    output = [
      "** (CompileError) lib/demo.ex:12: undefined function missing/0",
      "    lib/demo.ex:2: Demo.run/0",
      "web/app.ts(4,9): error TS2304: Cannot find name 'missing'.",
      "error[E0425]: cannot find value `missing` in this scope",
      " --> src/main.rs:7:5"
    ]

    assert Diagnostics.parse(output, root) == [
             %{
               file: "lib/demo.ex",
               line: 12,
               column: nil,
               message: "undefined function missing/0"
             },
             %{
               file: "web/app.ts",
               line: 4,
               column: 9,
               message: "error TS2304: Cannot find name 'missing'."
             },
             %{
               file: "src/main.rs",
               line: 7,
               column: 5,
               message: "error[E0425]: cannot find value `missing` in this scope"
             }
           ]
  end

  test "rejects runtime stack frames, missing files, and files outside the project", %{root: root} do
    outside = Path.join(System.tmp_dir!(), "outside.ex")
    File.write!(outside, "bad\n")
    on_exit(fn -> File.rm(outside) end)

    output = [
      "** (RuntimeError) boom",
      "    lib/demo.ex:2: Demo.run/0",
      "missing.ex:3: error: no such module",
      "#{outside}:1: error: outside"
    ]

    assert Diagnostics.parse(output, root) == []
  end

  test "cycles diagnostics and builds an editable modal", %{root: root} do
    items =
      Diagnostics.parse(
        [
          "lib/demo.ex:2: error: first",
          "lib/demo.ex:3: error: second"
        ],
        root
      )

    state = %Tidex.State{
      diagnostics: %{test: items, server: []},
      diagnostic_indices: %{test: 0, server: 0}
    }

    assert Diagnostics.current(state, :test).line == 2
    assert Diagnostics.modal(state, :test).title == "compile error 1/2"

    state = Diagnostics.cycle(state, :test, -1)
    assert Diagnostics.current(state, :test).line == 3
    assert Diagnostics.modal(state, :test).title == "compile error 2/2"
  end
end
