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
