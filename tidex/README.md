# Tidex

A language-agnostic development workbench built on
[Termex](../termex).

This first slice draws a fixed dashboard, quits on `q`, and runs one
hardcoded command on `t` (`echo hello from tidex`). Command output is
captured and shown on the next render.

```bash
cd tidex
mix deps.get
mix test
mix tidex
```

`mix tidex` needs a real TTY. Tests inject a `Termex.Device` backed by
`StringIO`, so they do not.
