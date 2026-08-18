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
| [`examples/proj1/`](examples/proj1) | Fixture app Tidex operates on (not Tidex itself) |

Project label and commands live in [`tidex.conf`](tidex.conf) (walked from
cwd toward `/`):

```
project: exmex-talk
test: mix test
server: python3 -m http.server 4000
browser: http://localhost:4000
file1: README.md
```

`file1`–`file4` are listed files. Missing keys are omitted. `1`–`4`
open the ones that are present. `0` always edits `tidex.conf`.

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

Not covered: real `stty` raw mode on an interactive terminal, or a real
`$EDITOR` session. Those paths are skipped or injected in tests.

## Run

From `tidex/`, on a real TTY. **Tidex operates on `examples/proj1`**, not
on Tidex itself:

```bash
cd tidex
mix tidex
```

`t` runs `mix test` in `examples/proj1` (one test fails on purpose).
`f` opens that failure. `mix tidex .` uses the current directory
instead. `mix tidex /path/to/other` uses that tree.
