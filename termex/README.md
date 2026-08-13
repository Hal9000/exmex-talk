# Termex

A small terminal UI runtime for Elixir.

Termex is not a curses wrapper. It grows only when an application — today,
[Tidex](../tidex) — needs another capability.

Current surface:

- clear the visible screen, move the cursor, write text
- box drawing: horizontal line, vertical line, corners
- clipped text regions so content stays inside a pane
- single-key input, including a keyboard process that sends keys as messages
- yield the terminal to an external program, then resume raw mode

Drawing and input go through an injectable `Termex.Device`, so tests can
use `StringIO` instead of a real TTY.

```bash
cd termex
mix test
```
