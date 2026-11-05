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

`q` always quits. The Help and Git boxes swallow most other keys.
Server operation stays on the lobby and has no takeover.

## Lobby chrome (snapshot)

Home is a lobby: one full-screen unicode status box, **grouped text**
(not little boxes). Two columns Test|Server, Git|Files, then `? help` /
`q quit`.

**Modal (a box you pull up and dismiss):** help, git, and failures.
They are content-sized boxes on the lobby. Setup still takes over the
screen with a 1-line menu outside the border.

**Not modal:** Test and Server groups. They update in place.

**Lobby labels:** section headings report state in reverse video
(`Test idle`, `Server down`, `Git main`). Keyed rows contain actions
only (`t  run tests`, `s  start`, `g  open git`).

**Test line:** idle → running → pass/fail. `N` updates as configured
ExUnit or Minitest failure headers stream (`Tidex.Failures` on each log
line). A failed run with no parsed blocks still reports `fail`.
`f  view failures` opens the box.

**Files:** `0  tidex.conf`, then `1`–`4`.

**Server:** stays on the lobby. `s` starts or restarts, `x` stops, and
`b` browses. Output is retained without replacing the lobby.
Occupancy/readiness is later; see **Server group: standing vs flash**.

**Termex (current, for the talk):** clip plus Help-specific prose wrap;
bold/reverse/dim and named ANSI colors. Tidex re-reads terminal
dimensions before redraw, with an 80×24 fallback; no SIGWINCH.

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

There are two fixtures: `proj1` (Elixir/ExUnit) and `ruby_calc`
(Ruby/Minitest). `test_format:` selects the small failure parser;
`test:` remains the arbitrary command. Setup guesses Ruby from
`Gemfile`, `Rakefile`, or `.ruby-version`. A language picker is later.

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
rule. It blanks the interior so the lobby does not bleed through. The
failure box uses it (`kind: :fail`, 60×8); Help and Git are converted.
Setup still takes over the screen.

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
  lobby so it is not the status groups. Setup’s sheet menu still sits
  *outside* the border; it should move inside when setup is converted.

**Window on large text**

- `write_region` still **clips** each line (CSI-safe). Help wraps its
  plain prose before drawing and scrolls the modal body. If an optional
  Server log box exists later, it should scroll its clipped log.
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

**Git:** a 60–64 column, 10–12 row modal. It clips status and command
output, follows the tail, and scrolls with arrows/PgUp/PgDn. Add,
commit, and push stay in the centered footer. It remains a status view,
not a full Git client.

**Crude sizes** (highly negotiable, two constants, not a layout DSL):
help ~50×10, centered. On 80×24 a content-sized box still leaves lobby
visible around it.

Setup is the remaining takeover. If every interesting box starts
maximized, we have sheets again.

**Failure view** fits a small bordered box (name, file:line, snippet,
`e` / left-right / `esc`). Maximize could show more of the hidden log.

## Terminal resize (SIGWINCH)

Tidex re-reads `:io.columns()` / `:io.rows()` before redraw and falls
back to 80×24 when detection fails. Resize therefore applies on the
next key, command line, command exit, or Git poll.

The remaining gap is an idle screen with no event:

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

- **Meat** (`tidex.conf`): `project`, `test`, `test_format`, `server`,
  `browser`, `editor`, `file1`–`file4`. How to operate the tree. Walk
  from cwd.
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

**Standing** (until the situation changes), in the section heading:

- Status: `down`, `up`, `starting` (job alive, not listening yet).
- Error: job exited, `stop failed`, leftover listener after `x`.
- Warning: `port in use`, `already listening` (unmanaged).

**Flash** (~3 seconds, then gone): purely informational. “started”,
“already down”, “restarted”. Not a substitute for standing status —
`Server up` stays after “started” fades.

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

`python3 -m http.server` was this repo’s stub and generic fallback. It
was a hidden, unnecessary dependency and is now removed. A project with
no `server:` says `not configured`; Tidex does not invent a language
runtime. Language fixtures get explicit foreground servers only when
the fixture needs one.

Tidex now owns **its job** through `Tidex.ServerJob` and erlexec. The
configured foreground shell command runs in a dedicated OS process
group. Stop, restart, and quit send TERM to the group, wait, escalate
to KILL, and reap it. Commands that daemonize or create a new session
can escape and are explicitly unsupported.

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
lobby is start-if-down, and the same `s` restarts when already up.
Restart should wait until the port is free (or a short timeout) before
spawn.

### Implemented code phases

Keep these as separate commits/checkpoints; do not land one opaque
lifecycle rewrite.

1. **Python default removed; deterministic fixtures added.**
   `server:` is optional in config and state. The lobby shows
   `not configured`; `s` / `x` are no-ops when absent and `b` requires
   a configured `browser:`. `proj1` uses a tiny foreground Elixir HTTP
   script and `ruby_calc` has no unrelated server. Test fixtures cover
   a TCP listener that prints `READY`, a parent/child process tree, and
   a process that ignores TERM, on unique ephemeral ports.

2. **Process tree owned and stopped.** Supervised `Tidex.ServerJob` is
   separate from generic test/Git commands. It stores the
   Port, OS pid, process-group id, and generation ref. Launch the
   foreground command in a new process group. `stop` sends TERM to the
   group, waits, escalates to KILL, reaps the Port, and returns a
   confirmed result. Erlexec supplies the Linux/macOS process manager;
   the target-platform helper is embedded in the escript.

3. **Lifecycle state made truthful.** `starting`, `up`, `down`,
   `start failed`, and `stop failed` do not claim success before it is
   known. Stop is idempotent. Restart is confirmed stop followed by
   start; stale output/exit messages from an older generation cannot
   alter the new job. Tests cover natural exit, TERM, KILL escalation,
   quit cleanup, repeated stop, and rapid restart.

4. **Conservative port awareness added.** Tidex parses a local TCP port
   from `browser:` when possible. It detects free/listening before start and
   after stop. A live owned job with a closed port is `starting`; a
   listener is occupancy, not application health. If the port was
   already occupied, report `busy, unmanaged` and do not start or kill
   it. If it remains occupied after stopping our group, report an
   orphan/stop failure. Do not use `ps | grep`, and never automatically
   kill an arbitrary listener pid.

5. **Real-platform acceptance.** Linux lifecycle and real-TTY
   start/restart/stop/quit checks pass with no remaining process and an
   immediately reusable port. A macOS run remains required. Docker,
   remote URLs, HTTP health checks, and unmanaged-process kill prompts
   stay outside this repair.
