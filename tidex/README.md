# Tidex

A language-agnostic development workbench built on
[Termex](../termex).

Home is a **lobby**: grouped commands (Test, Server, Git, Files) live
on the status screen. `t` runs tests and stays on the lobby. The Test
group shows `running N fail` with a live fail count as ExUnit `N)`
blocks arrive, then `pass`, `N fail`, or `fail`. `f` opens a failure box on the
lobby; left/right cycle, `e` edits that file, `esc` closes. The full
test log is kept but not shown.
`?` opens a help box over the lobby. Tab or arrows select a topic and
Enter opens explanatory text; arrows and PgUp/PgDn scroll it. Esc
returns to the topic list, then closes Help. `s` starts or restarts the
server directly from the lobby. `g` opens a scrollable Git box over the
lobby; setup is the remaining replacement sheet. Modal key hints occupy
a one-line footer separated
from the body by a horizontal rule; they are centered and use the same
bright-cyan accent as the modal frame.
Label and commands come from `tidex.conf` in the project (or a parent
directory): `project`, `test`, `test_format`, optional `server` /
`browser`, `editor`, and optional `file1`–`file4`. Without `server`,
the lobby reports `not configured` and disables server controls rather
than assuming Python or another runtime. Missing `project` defaults to that
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
| `f` | open the failure box (no-op if none) |
| `e` | editor at the current failure (while the box is open) |
| `s` | start or restart the server from the lobby |
| `x` | stop server |
| `b` | open browser URL |
| `0` | edit `tidex.conf` |
| `1`–`4` | open `file1`–`file4` from `tidex.conf` (missing key = no row) |
| arrows, PgUp/PgDn | navigate or scroll the open Help or Git box |
| left / right | cycle parsed test failures (while the box is open) |
| `?` | show/hide help |
| `g` | show/hide the Git box |
| `a` / `c` / `p` | add (`-u`) / commit / push (while git is open) |
| `esc` | close the current box or sheet |
| `q` | quit |

Failure navigation supports `test_format: exunit` (the default for Mix
projects) and `test_format: minitest` (the default for detected Ruby
projects). Use `test_format: none` for an arbitrary command whose output
Tidex should not parse. The configured `test:` command remains the
source of truth; this is deliberately not a language/plugin framework.
[`examples/ruby_calc`](../examples/ruby_calc) is the small Ruby fixture.

The lobby bolds the key letter next to each command (`t  idle`,
`s  down`, `0  tidex.conf`, …). Test and Server statuses use aligned
reverse-video fields. Modal frames use bright cyan as an active-layer
accent, and the lobby dims behind an open modal. `NO_COLOR` removes
these treatments while preserving alignment.

```bash
cd tidex
mix deps.get
mix test
mix escript.build
cd ../examples/proj1
../../tidex/tidex
```

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
