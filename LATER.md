# Later

Ideas we agreed not to build yet.

## `b` over SSH

Tidex is useful over SSH. `b` is not: it runs `open` / `xdg-open` on the
remote host, and `browser:` `localhost` is that host’s loopback.

**When we do it**

- After the “see one failure” view exists, or when we actually SSH and
  press `b`.
- Do not ask at startup. Only on the first `b` in a session that looks
  remote.

**Approach**

- Heuristic: `SSH_CONNECTION` (or `SSH_CLIENT` / `SSH_TTY`). Not a proof.
  tmux can lie; `ssh localhost` looks remote; `open` on a Mac console can
  still pop a window on the wrong seat.
- Not remote → `b` as today.
- Remote → overlay: say the URL, say open is **this machine** (the SSH
  host), ask `y`/`n`.
- Cache that answer in memory until Tidex exits. Do not write `~/.tidex`.
- `y` → later `b` opens without asking.
- `n` → do not open; later `b` still **shows the URL**. Cache is “open or
  don’t,” not “ignore `b`.”
- `esc` → cancel this keypress only. Do not cache `n`.
- “Copyable” means select in the terminal. Do not promise the clipboard
  (OSC 52 is often disabled).
- The printed URL is the remote loopback unless they forwarded a port.
  Mention `ssh -L`; do not rewrite the host.

False SSH yes costs one question. False no is today’s `b`. Accept that.
Do not also try to detect a GUI.

## Boxes (not sheets)

Tentative. No radical decision. Replaces “sheet” with one box on the
lobby, drawn last; next lobby frame restores. Not a window manager.

- **Default:** no full-screen takeover. Git, help, setup, a failure, a
  splash — a box sized to the content.
- **Splash:** ack and dismiss (`y` / `n` / `esc`). Setup is already this.
  No maximize.
- **Small / capped:** help, one failure. Do not grow to the terminal
  just because the text is long.
- **Maximize:** escape hatch for a log (server, maybe git). Same widget,
  bigger pane. Not on every box. Same key to shrink (toggle), not a
  third verb. `esc` dismisses (lobby).
- **Commands:** bottom interior line of **that box**. When maximized,
  that is the last screen row. Exceptions: splash with keys in the body;
  lobby, which is the menu.
- **Borders:** we already draw unicode boxes with a title in the top
  edge (`─ status ────`). Keep a border on anything that sits on the
  lobby so it is not the status groups. Today’s “sheet menu” sits
  *outside* the border; it should move inside.

**Window on large text**

- Today: `write_region` **clips** each line (CSI-safe). No wrap. Scroll
  (follow tail, arrows / PgUp / PgDn, pin) exists and is wired to the
  **server** overlay only. Help does not scroll; overflow vanishes.
- Goal: a box on a long buffer scrolls. Wrap is **not** global.
- **Clip** (default): logs, stacktraces, compiler columns.
- **Wrap:** prose (help, splash) when clipped lines read badly.
- Maximize = more columns (less clip / fewer wraps) and more rows.

Internally, wrap vs clip can be options on one function (`write_region`
or a sibling), not two pipelines.

**Server minimized:** fairly wide, several lines, stuck on the tail
(`:follow`). Clip, do not wrap. New lines stay at the bottom until
PgUp. Feels like a console — sit it **low**, not centered.

**Help:** midsize, roughly one topic. Search later. Maximize shows
longer lines and more lines.

**Crude sizes** (highly negotiable, two constants, not a layout DSL):
help ~50×10, centered; server log ~70×8, low. On 80×24 a 70-wide box
still leaves a little lobby visible.

**Do not build yet** except as part of the failure view / first real
box. Small bordered box + clip + scroll + follow-tail is enough to
try. Add wrap when help actually reads badly. If every interesting box
starts maximized, we have sheets again.

**Failure view** fits a small bordered box (name, file:line, snippet,
`e` / left-right / `esc`). Maximize could show more of the hidden log.

## Terminal resize (SIGWINCH)

First detection (`:io.columns()` / `:io.rows()` at boot) almost always
works on a real TTY. We fall back to 80×24 if it does not (pipe, no
pty). The gap is **stale size**: we snapshot once and never look again.

Not too much trouble. Not before boxes have real sizes. Relayout (box
geometry, 70×8 tail, scroll height, 16×12 floor) is the work; the
signal is small.

- **Cheaper:** re-read width/height at the start of every `View.render`.
  Already redraw on keys, log lines, git polls. Resize applies on the
  next event. Idle lobby stays stale until a key or a git tick. Usually
  enough.
- **SIGWINCH:** OTP `:os.set_signal(:sigwinch, :handle)` → UI process
  redraws while idle. Polish. Windows has no SIGWINCH; ignore until we
  care.

Not a Termex feature. Do not put it ahead of the failure box.
