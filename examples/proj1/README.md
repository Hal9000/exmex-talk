# proj1

Talk-repo fixture: a tiny Elixir app for **Tidex to operate on**. It is
not Tidex. One test fails on purpose so `t` then `f` has a failure box.

Build Tidex, then run it here on a real TTY:

```bash
cd ../../tidex
mix escript.build
cd ../examples/proj1
../../tidex/tidex
```

The command uses its current directory, so that opens this project. `0`
edits this `tidex.conf`. Its configured server is the foreground
`server.exs` Elixir script; the fixture has no Python dependency.
