# Tidex

A language-agnostic development workbench built on
[Termex](../termex).

Home is a **lobby**: grouped commands (Test, Server, Git, Files) live
on the status screen. `t` runs tests and stays on the lobby: a failure
count and the current failure, left/right to cycle, `e` to edit that
file. The full test log is kept but not shown. `s`, `g`, and `?` open
one sheet at a time; `esc` returns to the lobby.
Label and commands come from `tidex.conf` in the project (or a parent
directory): `project`, `test`, `server`, `browser`, `editor`, and
optional `file1`–`file4`. Missing `project` defaults to that
directory's name. Missing file keys add no row and no digit. Writing a
new file lists `README.md` / `mix.exs` / `package.json` / `Cargo.toml` /
`go.mod` when those names exist in that directory. `~/.tidex/tidex.conf`
holds a user `editor` fallback and a `dir: name` catalog; it is not on
the walk toward `/`. A project file wins per key. If no project file is
found, Tidex asks before writing one (`y` cwd, `g` git root, `n`/`esc`
skip). `$HOME`, `/`, and `/tmp` are not permitted; `y` is omitted.

| Key | Action |
| --- | --- |
| `t` | run tests (lobby shows the count and one failure) |
| `s` | open the server sheet; press again to start or restart |
| `x` | stop server |
| `b` | open browser URL |
| `e` | editor; opens the current failure at line when there is one |
| `f` | edit `tidex.conf` |
| `1`–`4` | open `file1`–`file4` from `tidex.conf` (missing key = no row) |
| arrows, PgUp/PgDn | scroll the open server sheet |
| left / right | cycle parsed test failures |
| `?` | show/hide help |
| `g` | show/hide git |
| `a` / `c` / `p` | add (`-u`) / commit / push (while git is open) |
| `esc` | close the current sheet |
| `q` | quit |

The lobby bolds the key letter next to each command (`t  idle`,
`s  down`, `f  tidex.conf`, …). After a failing run the Test group
shows `t  N failing` and the current file:line.

```bash
cd tidex
mix deps.get
mix test
mix tidex
```

`mix tidex` needs a real TTY. Tests inject a `Termex.Device` backed by
`StringIO` and drive the UI with messages, so they do not.

The runtime is a small OTP tree: `Tidex.Supervisor` starts a git poller
and `Tidex.Workers` (`DynamicSupervisor`) for the keyboard and command
jobs. The UI process is the only one that draws.
