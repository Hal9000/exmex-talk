# Tidex

A language-agnostic development workbench built on
[Termex](../termex).

Fixed two-pane layout: a **status** pane (project, tests, server) and an
**output** pane. `t` runs the project test command and streams lines as
they arrive. `s` starts or restarts a server. `q` quits.

The default test command is `mix test` when `mix.exs` is present. The
default server command is `python3 -m http.server 4000`.

```bash
cd tidex
mix deps.get
mix test
mix tidex
```

`mix tidex` needs a real TTY. Tests inject a `Termex.Device` backed by
`StringIO` and drive the UI with messages, so they do not.
