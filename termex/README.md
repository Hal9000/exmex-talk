# Termex

A small terminal UI runtime for Elixir.

Termex is not a curses wrapper. It grows only when an application — today,
[Tidex](../tidex) — needs another capability.

Current surface:

- clear the visible screen, move the cursor, write text
- box drawing: horizontal line, vertical line, corners
- clipped text regions so content stays inside a pane
- single-key input, including a keyboard process that sends keys as messages

Drawing and input go through an injectable `Termex.Device`, so tests can
use `StringIO` instead of a real TTY.

```elixir
device = Termex.Device.stdio()

Termex.with_raw_mode(device, fn ->
  Termex.clear_visible(device)
  Termex.box(device, 1, 1, 40, 8, title: "status")
  Termex.write_clipped(device, 2, 2, 38, "hello")
  Termex.read_key(device)
end)
```

```bash
cd termex
mix test
```
