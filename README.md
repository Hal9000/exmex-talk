# exmex-talk

Case study code for an Elixir conference talk: a small application
(**Tidex**) that grows a small library (**Termex**) only as it needs
new capability.

```
Tidex  →  Termex drawing/input  →  external command  →  streamed output back into Tidex
```

| Project | Role |
| --- | --- |
| [`termex/`](termex) | Terminal UI runtime: clear, cursor, write, boxes, clipped regions, keys, yield |
| [`tidex/`](tidex) | Workbench: lobby, test/server/git/help, browser, editor, OTP supervision |
| [`examples/proj1/`](examples/proj1) | Elixir/ExUnit fixture Tidex operates on |
| [`examples/proj2/`](examples/proj2) | Static test-command compile-error demonstration |
| [`examples/proj3/`](examples/proj3) | Static server-start compile-error demonstration |
| [`examples/ruby_calc/`](examples/ruby_calc) | Ruby/Minitest fixture using the same failure box |

Project label and commands live in [`tidex.conf`](tidex.conf) (walked from
cwd toward `/`):

```
project: exmex-talk
test: mix test
test_format: exunit
file1: README.md
```

`file1`–`file4` are listed files. Missing keys are omitted. `1`–`4`
open the ones that are present. `0` always edits `tidex.conf`.
`test_format` is `exunit`, `minitest`, or `none`; it selects only the
small failure-output parser, while `test` remains an arbitrary command.
`server` and `browser` are optional; Tidex does not assume a language
runtime when they are absent. Git support defaults to the nearest enclosing
repository; set `git: off` when that repository is irrelevant to the project.

`project` is the status-pane label. If omitted, it defaults to a
`dir: name` entry in `~/.tidex/tidex.conf`, then the directory that
contains `tidex.conf` (or cwd when the file is missing). `editor`
falls back to `~/.tidex/tidex.conf`, then `$VISUAL` / `$EDITOR` / `vi`.
`~/.tidex/` is not on the walk toward `/`.

If no `tidex.conf` is found, Tidex prompts before writing one: `y` writes
in cwd, `g` writes at the nearest git root (when that path differs and
is not `$HOME` / `/` / `/tmp`), `n` or `esc` skips. `$HOME`, `/`, and
`/tmp` are not permitted for `y`; the overlay says so and omits that key.

Tidex depends on Termex locally:

```elixir
{:termex, path: "../termex"}
```

## Tests

Most of this is tested without a TTY. Termex writes ANSI sequences to an
injectable device; Tidex feeds keys as messages and injects (or really
runs) commands.

```bash
cd termex && mix test
cd tidex && mix deps.get && mix test
```

Tidex uses erlexec for owned server process groups. Building Tidex
therefore needs `make` and a C++ compiler; the built escript embeds the
target-platform helper.

Not covered: real `stty` raw mode on an interactive terminal, or a real
`$EDITOR` session. Those paths are skipped or injected in tests.

## Run

Build the command, then run it from the project Tidex should operate on.
This requires Elixir and Erlang/OTP:

```bash
cd tidex
mix escript.build
cd ../examples/proj1
../../tidex/tidex
```

`t` runs `mix test` in `examples/proj1` (one test fails on purpose).
`f` opens that failure.

`examples/proj2` and `examples/proj3` are intentionally uncompilable.
In `proj2`, press `t` then `f` to inspect a test-command compile error.
In `proj3`, press `s`; its server compile-error modal opens automatically,
while `v` remains the command for raw server output.

For the Ruby fixture, run the same built command from
`examples/ruby_calc`. Its failing Minitest assertion opens in the same
failure box.

To install `tidex` on your `PATH`:

```bash
cd tidex
mix do escript.build + escript.install
export PATH="$HOME/.mix/escripts:$PATH"
```

Running `tidex` uses the current directory. `tidex /path/to/project`
uses another project tree. For in-tree development, `mix tidex` still
opens `examples/proj1`, while `mix tidex .` uses the current directory.
