# exmex-talk

Case study code for an Elixir conference talk: a small application
(**Tidex**) that grows a small library (**Termex**) only as it needs
new capability.

```
Tidex  →  Termex drawing/input  →  external command  →  streamed output back into Tidex
```

| Project | Role |
| --- | --- |
| [`termex/`](termex) | Terminal UI runtime: clear, cursor, write, boxes, clipped regions, keys |
| [`tidex/`](tidex) | Workbench: two-pane dashboard, streaming tests, server start/restart |

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

Not covered: real `stty` raw mode on an interactive terminal. That path
is skipped automatically when stdin is not a TTY.

## Run

```bash
cd tidex
mix tidex
```

Keys: `t` runs tests, `s` starts or restarts the server, `q` quits.
