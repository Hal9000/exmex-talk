# Termex

A small terminal UI runtime for Elixir.

Termex is not a curses wrapper. It grows only when an application — today,
[Tidex](../tidex) — needs another capability.

Current surface:

- clear the visible screen, move the cursor, write text
- box drawing: horizontal line, vertical line, corners
- clipped text regions so content stays inside a pane (CSI is not width)
- bold, standard and bright foreground colors, and reverse video (SGR)
- key input: single bytes, arrow/page keys, and a keyboard process that
  sends keys as messages
- yield the terminal to an external program, then resume raw mode

Drawing and input go through an injectable `Termex.Device`, so tests can
use `StringIO` instead of a real TTY.

`Termex.color/2` and `Termex.reverse/1` return plain text when the
`NO_COLOR` environment variable is present.

```bash
cd termex
mix test
```
