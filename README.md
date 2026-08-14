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
| [`tidex/`](tidex) | Workbench: tests, server, git, browser, editor, two layouts, OTP supervision |

Project commands live in [`tidex.exs`](tidex.exs) (walked from cwd toward `/`):

```elixir
%{
  test: "mix test",
  server: "python3 -m http.server 4000",
  browser: "http://localhost:4000",
  editor: System.get_env("EDITOR") || "vi"
}
```

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

```bash
cd tidex
mix tidex
```

Keys: `t` tests, `s` start/restart server, `x` stop, `b` browser, `e`
editor, `l` layout, arrows scroll output, left/right cycle failures,
`?` help, `g` git, `q` quit.
