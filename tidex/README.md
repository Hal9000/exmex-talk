# Tidex

A language-agnostic development workbench built on
[Termex](../termex).

Home is a **lobby**: grouped status (Test, Server, Git) and a menu.
`t`, `s`, `g`, and `?` open one sheet at a time; `esc` returns to the
lobby. Label and commands come from `tidex.conf` in the project (or a
parent directory): `project`, `test`, `server`, `browser`, `editor`,
and optional `file1`–`file4`. Missing `project` defaults to that
directory's name. Missing file keys add no row and no digit. Writing a
new file lists `README.md` / `mix.exs` / `package.json` / `Cargo.toml` /
`go.mod` when those names exist in that directory. If the file is
missing, Tidex asks before writing one (`y` cwd, `g` git root, `n`/`esc`
skip). `$HOME`, `/`, and `/tmp` are not permitted; `y` is omitted.

| Key | Action |
| --- | --- |
| `t` | open the test sheet; press again to run tests |
| `s` | open the server sheet; press again to start or restart |
| `x` | stop server |
| `b` | open browser URL |
| `e` | editor; opens the current failure at line when there is one |
| `f` | edit `tidex.conf` |
| `1`–`4` | open `file1`–`file4` from `tidex.conf` (missing key = no row) |
| arrows, PgUp/PgDn | scroll the open test or server sheet |
| left / right | cycle parsed test failures |
| `?` | show/hide help |
| `g` | show/hide git |
| `a` / `c` / `p` | add (`-u`) / commit / push (while git is open) |
| `esc` | close the current sheet |
| `q` | quit |

The footer bolds the key letter (`test`, `start`, `xstop`, …).

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
