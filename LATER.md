# Later

Ideas we agreed not to build yet. The failure box is in. Do not invent
the next slice until a real TTY look (`mix tidex`).

## Failure box

`f` opens a 60×8 modal on the lobby (`fail N/M`, name, file:line, two
snippet lines, `e  edit  left/right  esc`). No-op if none. `esc` or `f`
closes. Left/right and `e` work only inside. `0` edits `tidex.conf`.
Lobby `e` does nothing.

Maximize (more of the hidden test log) later. Do not dump the ExUnit
`1)` block into the box.

## Overlay keys (seal)

`q` always quits. The Help box and Git takeover swallow most other
keys. The leftover **server** takeover still leaks lobby verbs (`t`,
`0`, `1`–`4`, `x`, `b`, …). `f` from there opens the failure box and
drops the takeover. That takeover should go away.

## Lobby chrome (snapshot)

Home is a lobby: one full-screen unicode status box, **grouped text**
(not little boxes). Two columns Test|Server, Git|Files, then `? help` /
`q quit`.

**Modal (a box you pull up and dismiss):** help, git, setup. Help and
the failure box are content-sized boxes on the lobby. Git and setup
still take over the screen with a 1-line menu outside the border.

**Not modal:** Test and Server groups. They update in place.

**Hotkey line:** `s  down` means key `s` plus **status** `down`, not a
command named down. The same helper draws verbs (`x  stop`) and status
(`t  idle`, `g  main`). Confusing. Change later, not now.

**Test line:** idle → `t  idle`; after start → `t  - pass  N fail`.
`N` updates as ExUnit `1)` / `2)` headers stream (`Tidex.Failures` on
each log line). Passes stay `-` until a summary is parsed. Failed run
with no parsed blocks → `t  fail`. `f  fail` opens the box.

**Files:** `0  tidex.conf`, then `1`–`4`.

**Server (desired):** stay on the lobby. `s` does the job (start or
restart), `x` stop, `b` browse. Do not open a second screen. Today
`s` still opens a leftover full-screen log; that is wrong for this
model. Occupancy/restart is a later section. Live facts on the Server
group: see **Server group: standing vs flash**.

**Termex (current, for the talk):** clip, no wrap; bold only, no hues;
size `:io.columns` / `:io.rows` once at boot, 80×24 fallback; no
SIGWINCH. Resize and colors are later sections.

## Packaging

Tidex is a **tool** (`tidex`, like an editor or linter). It is **never**
a `mix.exs` dependency of the project under test.

- Recommend an **escript** named `tidex`.
- Keep in-repo `mix tidex` for developing Tidex itself.
- Elixir users: `mix escript.install`.
- Non-Elixir: a self-contained binary later (Bakeware / Burrito).
- Both end on `tidex` on PATH, not `mix tidex`.

**Termex is not a Hex package yet.** Fold it into the Tidex artifact.
Split when a second application needs Termex. The talk thesis stays
application-first: Termex grows only when Tidex needs a capability.

## Talk repo / examples

Do not use Tidex to develop Tidex. Examples are **talk-repo fixtures**,
not a Tidex feature. `examples/proj1/` is a tiny Elixir app with its
own `tidex.conf`. `mix tidex` (from `tidex/`) opens that project;
`test:` / `server:` run in that directory. `mix tidex .` uses cwd.

Two languages later (an Elixir fixture and a Ruby one). Setup already
guesses `test:` from `mix.exs` / `package.json` / `Cargo.toml` /
`go.mod`. No Gemfile / Ruby yet. A language picker at setup is later.

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

`Tidex.Modal` is that draw: content-sized, centered, capped, with a
centered bright-cyan command footer separated by its own horizontal
rule. It blanks the interior so the lobby does not bleed through. The failure box uses
it (`kind: :fail`, 60×8), and Help is the first experimental conversion.
Git / setup still take over the screen.

- **Default:** no full-screen takeover. Git, help, setup, a failure, a
  splash — a box sized to the content. **Not** the Server group: that
  stays lobby text.
- **Splash:** ack and dismiss (`y` / `n` / `esc`). Setup is already this.
  No maximize.
- **Small / capped:** help, one failure. Do not grow to the terminal
  just because the text is long.
- **Maximize:** escape hatch for a long buffer (maybe git, maybe a
  server log if we ever want one). Same widget, bigger pane. Not on
  every box. Same key to shrink (toggle), not a third verb. `esc`
  dismisses (lobby). Operating the server does not require this.
- **Commands:** bottom interior line of **that box**. When maximized,
  that is the last screen row. Exceptions: splash with keys in the body;
  lobby, which is the menu.
- **Borders:** we already draw unicode boxes with a title in the top
  edge (`─ status ────`). Keep a border on anything that sits on the
  lobby so it is not the status groups. Today’s “sheet menu” sits
  *outside* the border; it should move inside.

**Window on large text**

- `write_region` still **clips** each line (CSI-safe). Help wraps its
  plain prose before drawing and scrolls the modal body; the Server
  overlay also scrolls its clipped log.
- Goal: a box on a long buffer scrolls. Wrap is **not** global.
- **Clip** (default): logs, stacktraces, compiler columns.
- **Wrap:** prose (help, splash) when clipped lines read badly.
- Maximize = more columns (less clip / fewer wraps) and more rows.

Internally, wrap vs clip can be options on one function (`write_region`
or a sibling), not two pipelines.

**Server log box:** optional later, not how you run the server. Status,
errors, and warnings belong in the Server **group**. If a tail box
exists someday: fairly wide, several lines, stuck on the tail
(`:follow`), clip, sit **low**. Not a modal to start/stop.

**Help:** a six-topic menu in one modal. Tab/arrows select, Enter
replaces the menu with wrapped explanatory text, arrows/PgUp/PgDn
scroll, and Esc returns to the menu. Search and maximize are later.

**Crude sizes** (highly negotiable, two constants, not a layout DSL):
help ~50×10, centered. On 80×24 a content-sized box still leaves lobby
visible around it.

Do not convert another takeover until the interactive Help experiment
is accepted. If every interesting box starts maximized, we have sheets
again.

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

## Colors and `tidex.theme`

Informal. Behind the failure box. Today: bold hotkeys, reverse status
fields, bright-cyan modal frames, and a dimmed lobby behind a modal.
Child commands may still emit their own ANSI.

**First feature is not light/dark.** We do not paint a background; the
terminal already has a theme. Bare minimum: semantic ANSI on this
terminal’s palette, plus bold. Do not set default fg/bg. `NO_COLOR` /
dumb `TERM` → bold only.

**ANSI:** 16 names: black/red/green/yellow/blue/magenta/cyan/white and
their bright variants. Not 256 or truecolor.

**Semantic knobs, few:** active modal frame (bright cyan), modal
background (dim), fail (red), pass/ok (green), optional warn (yellow).
Not per-pane chrome. Pass/fail on the Test line is the next color that
means something.

**Two files, same `key: value` syntax.** Colors are per-project
*appearance*, not meat. Do not put them in `tidex.conf`.

- **Meat** (`tidex.conf`): `project`, `test`, `server`, `browser`,
  `editor`, `file1`–`file4`. How to operate the tree. Walk from cwd.
- **Appearance** (`tidex.theme`, name negotiable): colors, later maybe
  box sizes. `~/.tidex/tidex.theme` (defaults) and a file next to the
  project `tidex.conf` (this lobby). Local wins per key; omit to
  inherit. Same merge idea as today. Catalog and `editor:` stay where
  they are.

Committing the theme file is optional (demo look vs personal accent).
Checking in hex / “assume dark” is the usual mistake; named ANSI
(`red`, `bright-red`, `default`) is portable.

User-only colors were a wrong collapse of “not in `tidex.conf`.”
Per-project colors belong in the project tree, in the second file.

## Server group: standing vs flash

Realtime updates to the **Server portion of the lobby** are the
feature. Not a second screen. Do not dump `server:` stdout into that
group (the log can still be accumulated, unseen).

**Standing** (until the situation changes), extra lines like git
`dirty` / `untracked`:

- Status: `down`, `up`, `starting` (job alive, not listening yet).
- Error: job exited, `stop failed`, leftover listener after `x`.
- Warning: `port in use`, `already listening` (unmanaged).

**Flash** (~3 seconds, then gone): purely informational. “started”,
“already down”, “restarted”. Not a substitute for standing status —
`s  up` stays after “started” fades.

Three seconds is a guess. Needs a timer (`Process.send_after` →
redraw). Git polls already wake the UI; this is a one-shot, not a
clock. Do not invent a toast stack. One flash line under Server is
enough. A new standing fact replaces a flash.

Splash (modal) stays only for a **decision**: “port in use, not our
job — kill? y/n.” Occupancy details are in the next section.

Do not build this before the failure box.

## Project server: up/down, occupancy, restart

The **project** server (`server:` / `browser:` in `tidex.conf`), not
anything inside Tidex. Not Phoenix-centric: that command is whatever
the user configured (`mix phx.server`, `mix run --no-halt`, Puma,
Webrick, …). Puma is a Ruby HTTP server (Rack; often with Rails).
`python3 -m http.server` is only this repo’s stub.

Today we only know **our job**: we spawn `sh -c server:` behind an
Elixir Task/Port, set `:up` until that port exits or `x`. That is not
the listener, not ready, not a server started in another terminal.
`sh -c` plus killing the Task often kills the shell and **leaves the
real server** (bad kill). Occupancy after `x` detects that;
process-group / listener-pid kill is the repair.

**Do not** grep `ps` for the command line (two projects, rewritten
argv, BEAM). **Do** keep the OS pid of *our* spawn: gone → we are
down; still there after `x` → stop failed. Age/`etime` is when that
pid started, not when it accepted a socket. Idle LISTEN and hung look
the same in `ps`. Age ≠ ready (fast servers vs compile/boot). No
global “older than N seconds → up.”

**LISTEN on the `browser:` port** (occupancy, not HTTP GET) is the
modest probe. Something else can own the port. Boot can still be in
progress.

- In use at Tidex start → not *this* job. Might be another terminal,
  an orphan from a previous Tidex, or another app. Label: “already
  listening,” not “never Tidex.”
- In use after `x` → bad kill (strong case).
- In use before (re)start → port busy, second start will fail. If we
  just killed: leftover. If we never owned a job: outside/orphan.
  Say “port in use,” not “kill failed,” unless we just sent kill.
- Not in use after start → often “not yet,” not “bad start.” Job
  already exited → bad start (we already get `:exit`). Job alive,
  port still closed → `starting`. A check immediately after spawn
  false-fails slow boots. Retry, or show `starting` until LISTEN or
  the job dies.
- Not in use before kill → `x` is a no-op. Treat as down.

**Docker** (we do not use it): occupancy on the host still means
something is listening here. The LISTEN pid may be `docker-proxy`;
killing it may not stop the container. Do not design around Docker.
Pid-kill = “process that owns this port on this machine.”

**Anomalies:** standing facts under Server on the lobby (`starting`,
`port busy`, `stop failed`, `not listening`) — one line, like git
dirty. Splash only for a **decision**: “port in use, not our job —
kill? y/n.” Need the listening pid (`lsof`/`ss`), not occupancy alone.
Auto-kill is too sharp. Ask once per boot if busy and we have no job;
`n` remembered for that process. Persistent “busy, unmanaged” on the
Server group if they leave it.

Hung-but-listening is health (GET); later.

**Restart:** stop then start. Stop is a no-op if nothing to kill.
Restart when already dead is just start. No error. Desired: `s` on the
lobby is start-if-down, and the same `s` (or a later third key) is
restart when already up. Today `s` opens a leftover log screen, then
`s` again stop-then-starts. Restart should wait until the port is free
(or a short timeout) before spawn.

**Continuum to build later** (not before the failure box): (1) our
job + exit, (2) LISTEN on the browser port, (3) after `x` if still
LISTEN then kill listener pid/group, (4) optional splash at start if
busy and unmanaged. Skip command-line `ps` matching. Skip GET `/`.
