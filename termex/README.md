# Termex

A small terminal UI runtime for Elixir.

Termex is not a curses wrapper. It grows only when an application — today,
[Tidex](../tidex) — needs another capability.

This first slice:

- clear the visible screen
- move the cursor
- write text
- read a single key

Drawing and input go through an injectable `Termex.Device`, so tests can
use `StringIO` instead of a real TTY.

```elixir
device = Termex.Device.stdio()

Termex.with_raw_mode(device, fn ->
  Termex.clear_visible(device)
  Termex.write_at(device, 1, 1, "hello")
  Termex.read_key(device)
end)
```

```bash
cd termex
mix test
```
