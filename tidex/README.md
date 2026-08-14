# Tidex

A language-agnostic development workbench built on
[Termex](../termex).

Two layouts (`l` to toggle): a **status** pane (project, tests, server,
git) and an **output** pane. Commands come from `tidex.exs` in the
project (or a parent directory).

| Key | Action |
| --- | --- |
| `t` | run tests, stream output |
| `s` | start or restart server |
| `x` | stop server |
| `b` | open browser URL |
| `e` | editor; opens the current failure at line when there is one |
| `l` | toggle dashboard / output-focused layout |
| arrows, PgUp/PgDn | scroll the output pane (pins when not at the tail) |
| left / right | cycle parsed test failures |
| `?` | show/hide help overlay |
| `g` | show/hide git status overlay |
| `a` / `c` / `p` | add (`-u`) / commit / push (while git overlay is open) |
| `q` | quit |

```bash
cd tidex
mix deps.get
mix test
mix tidex
```

`mix tidex` needs a real TTY. Tests inject a `Termex.Device` backed by
`StringIO` and drive the UI with messages, so they do not.

The runtime is a small OTP tree: `Tidex.Supervisor` starts a git poller
and `Tidex.Workers` (`DynamicSupervisor`) for the keyboard and command
jobs. The UI process is the only one that draws.
