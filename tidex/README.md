# Tidex

A language-agnostic development workbench built on
[Termex](../termex).

Home is a **lobby**: grouped commands (Test, Server, Git, Files) live
on the status screen. `t` runs tests and stays on the lobby. The Test
group shows `running N fail` with a live fail count as recognized failure
blocks arrive, then `pass`, `N fail`, or `fail`. `f` opens parsed test
failures or compiler diagnostics; left/right cycle and `e` opens the
reported location. Test failures may also offer `s` for a project-source
candidate. `o` shows full output. `esc` closes or backs out. If nothing
structured was parsed, `f` opens the raw test output instead.
`?` opens a 64×18 help document over the lobby. It combines command
reference with short explanations of behavior and limitations; arrows and
PgUp/PgDn scroll it, and Esc closes it. The document shrinks and rewraps
to retain a terminal margin on smaller screens. `s` starts or restarts the
server directly from the lobby. `g` opens a scrollable Git box over the
lobby; its command menu stays fixed above the scrolling status and output,
with contextual controls in the footer. Initial setup uses the same modal
treatment. Other modal key hints occupy a one-line footer separated from
the body by a horizontal rule. Modals use a bright-cyan double-line outer
frame and thin internal dividers so they remain distinct from the single-line
lobby even when terminal dimming is subtle.
Label and commands come from `tidex.conf` in the project (or a parent
directory): `project`, `test`, `test_format`, optional `server` /
`browser`, `editor`, `git`, and optional `file1`–`file4`. `git` defaults
to `auto`, using the nearest enclosing repository; `git: off` suppresses
Git polling and controls for projects where that repository is irrelevant.
When auto-detection finds no repository, the Git box remains in place and
shows `[No Git repository]`.
Without `server`,
the Server box keeps its size but shows `[No server configured]`
instead of controls; Tidex does not assume Python or another runtime.
Missing `project` defaults to that
directory's name. Missing file keys add no row and no digit. Writing a
new file lists `README.md` / `mix.exs` / `package.json` / `Cargo.toml` /
`go.mod` when those names exist in that directory. `~/.tidex/tidex.conf`
holds a user `editor` fallback and a `dir: name` catalog; it is not on
the walk toward `/`. A project file wins per key. If no project file is
found, Tidex asks before writing one (`y` cwd, `g` git root, `n`/`esc`
skip). `$HOME`, `/`, and `/tmp` are not permitted; `y` is omitted.

| Key | Action |
| --- | --- |
| `t` | run tests (lobby shows `running` and a live fail count) |
| `f` | open parsed test failures, compiler diagnostics, or raw failed output |
| `e` | editor at the reported failure location |
| `s` | editor at a project-source candidate, when shown in Failure |
| `o` | inspect complete test output from a parsed Failure |
| `s` | start or restart the server from the lobby |
| `x` | stop server |
| `b` | open browser URL |
| `v` | inspect retained server output |
| `0` | edit `tidex.conf`; reload it when the editor returns |
| `1`–`4` | open `file1`–`file4` from `tidex.conf` (missing key = no row) |
| arrows, PgUp/PgDn | navigate or scroll the open Help or Git box |
| left / right | cycle parsed test failures or compiler diagnostics |
| `?` | open Help |
| `i` | show a compact Git branch and change-count summary |
| `g` | open the full Git status box |
| `a` / `l` / `c` / `p` | add (`-u`) / pull (`--ff-only`) / one-line commit / push (while Git is open) |
| `u` | ship: add `-u`, commit, pull `--rebase`, then push |
| `esc` | close the current box |
| `q` | quit |

Failure navigation supports `test_format: exunit` (the default for Mix
projects) and `test_format: minitest` (the default for detected Ruby
projects). Use `test_format: none` for an arbitrary command whose output
Tidex should not parse. The configured `test:` command remains the
source of truth; this is deliberately not a language/plugin framework.
[`examples/ruby_calc`](../examples/ruby_calc) is the small Ruby fixture.

Tidex launches a configured server as a foreground command in its own
OS process group. Stop, restart, and quit send TERM to the owned group
and escalate to KILL when necessary. For local `browser:` URLs the
lobby shows `starting` until the port listens, refuses to start over an
unmanaged listener (`port busy`), and never kills a process it did not
create. Commands that daemonize or detach into a new session are not
supported.

The lobby bolds the key letter next to each command (`t  idle`,
`s  down`, `0  tidex.conf`, …). Test and Server statuses use aligned
reverse-video fields. Modal frames use bright cyan as an active-layer
accent, and the lobby dims behind an open modal. `NO_COLOR` removes
these treatments while preserving alignment.

When OTP supports `SIGWINCH`, resizing redraws the lobby immediately
even while the UI is idle.

```bash
cd tidex
mix deps.get
mix test
mix escript.build
cd ../examples/proj1
../../tidex/tidex
```

Building Tidex compiles erlexec's small native process manager and
therefore requires `make` and a C++ compiler. The resulting escript
embeds and materializes the helper for the platform on which it was
built.

`mix test` tests Tidex. The built `tidex` command needs a real TTY and
uses the current directory by default. Pass a path to operate on another
project. For in-tree development, `mix tidex` opens
[`examples/proj1`](../examples/proj1) (a fixture app, not this tree), and
`mix tidex .` uses the current directory. Tests inject a `Termex.Device`
backed by `StringIO` and drive the UI with messages, so they do not need
a TTY.

The runtime is a small OTP tree: `Tidex.Supervisor` starts a git poller
and `Tidex.Workers` (`DynamicSupervisor`) for the keyboard and command
jobs. The UI process is the only one that draws.
