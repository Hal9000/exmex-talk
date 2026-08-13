# exmex-talk

Case study code for an Elixir conference talk: a small application
(**Tidex**) that grows a small library (**Termex**) only as it needs
new capability.

```
Tidex  →  Termex drawing/input  →  external command  →  output back into Tidex
```

| Project | Role |
| --- | --- |
| [`termex/`](termex) | Terminal UI runtime: clear, cursor, write, read a key |
| [`tidex/`](tidex) | Development workbench: dashboard, `q` to quit, `t` to run a command |

Tidex depends on Termex locally:

```elixir
{:termex, path: "../termex"}
```

## Tests

Most of this slice is tested without a TTY. Termex writes ANSI sequences
to an injectable device; Tidex feeds keys through the same device and
injects (or really runs) the `t` command.

```bash
cd termex && mix test
cd tidex && mix deps.get && mix test
```

Not covered yet: real `stty` raw mode on an interactive terminal. That
path is skipped automatically when stdin is not a TTY.

## Run

```bash
cd tidex
mix tidex
```

Keys: `t` runs `echo hello from tidex`, `q` quits.
