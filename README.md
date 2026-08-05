# ssh-workspace

SSH into a host and attach to a persistent terminal-multiplexer session in one
command — [tmux](https://github.com/tmux/tmux) if the remote host has it,
[GNU Screen](https://www.gnu.org/software/screen/) otherwise. If the connection
drops, it reconnects automatically and your session picks up exactly where it
left off.

Useful for long-running work on remote machines — builds, training runs,
interactive sessions — where a flaky network or a closed laptop lid shouldn't
kill your shell.

## Install

Copy the script somewhere on your `PATH` and make it executable:

```sh
curl -fsSL https://raw.githubusercontent.com/cschlick/ssh-workspace/main/ssh-workspace \
    -o ~/.local/bin/ssh-workspace
chmod +x ~/.local/bin/ssh-workspace
```

Requirements: `bash` and `ssh` locally, tmux or GNU Screen on the remote host
(`sudo apt install tmux` or `sudo apt install screen` on Debian/Ubuntu).

## Usage

```
ssh-workspace [options] HOST
ssh-workspace [options] USER@HOST
ssh-workspace                       # reconnect to the last workspace
```

Run without `-s` and the script lists the workspaces already on the host so
you can pick one by number — or type a name to create a new one:

```
Workspaces on picomol (tmux):
  1) workspace (attached)
  2) build (detached)
  3) claude (detached)
Select a number, or type a session name [1]:
```

Passing `-s NAME` skips the picker; non-interactive runs (no terminal) use
the default name `workspace`.

Each connection remembers where it went: run `ssh-workspace` with no host at
all and it reconnects straight to the last workspace (host, session, port,
and `-o` options included). Explicit flags override the saved values.

| Option | Description |
| ------ | ----------- |
| `-u USER` | SSH username |
| `-s SESSION` | Session name; skips the interactive picker |
| `-l` | List workspaces on the host and exit |
| `-m MODE` | Multiplexer: `auto`, `tmux`, or `screen` (default: `auto` — tmux if available, else Screen) |
| `-p PORT` | SSH port (default: SSH config or 22) |
| `-i FILE` | SSH identity file |
| `-o OPTION` | Additional SSH option; may be repeated |
| `-e TERM` | Terminal type (default: `xterm-256color`) |
| `-n` | Do not reconnect automatically |
| `-h` | Show help |

Examples:

```sh
ssh-workspace picomol                          # attach to "workspace" on picomol
ssh-workspace root@picomol                     # as root
ssh-workspace -s claude root@picomol           # separate named session
ssh-workspace -m screen picomol                # force GNU Screen
ssh-workspace -p 2222 -s admin alice@example.com
ssh-workspace -o ProxyJump=bastion root@internal-server
```

Running the same command from another machine steals the session
(`tmux new-session -A -D` / `screen -D -RR`), so you can walk from desktop to
laptop and reattach to the same shell.

Detach with `Ctrl-B d` (tmux) or `Ctrl-A d` (Screen), or exit the remote shell
to end the session.

Quality-of-life details: the terminal tab is titled `host:session` so multiple
workspaces are easy to tell apart, and the session listing and attach share
one SSH connection (`ControlMaster`), so the picker adds no extra auth prompt.
State (the last-workspace file and control sockets) lives in
`~/.local/state/ssh-workspace/`.

## Reconnect behavior

Keepalives (`ServerAliveInterval=15`) detect a dead connection within about
30 seconds. When the connection is lost:

- Reconnect attempts back off exponentially: 2, 4, 8, 16, 32 seconds.
- After about a minute without success, it pauses and waits — press **Enter**
  to resume retrying, or **Ctrl-C** to quit.
- Connections that fail instantly (bad credentials, connection refused) pause
  after 3 attempts instead of retrying on a timer.
- A session that was up for at least 30 seconds resets the backoff, so a brief
  blip after hours of work retries quickly.

Pass `-n` to disable reconnecting entirely.

## Compared to mosh

[mosh](https://mosh.org/) solves an overlapping problem at a different layer:
it replaces the SSH transport with its own UDP protocol, while ssh-workspace
keeps plain SSH and puts session persistence on the server.

Where ssh-workspace wins:

- **No dedicated ports.** Works over TCP port 22 like any SSH connection —
  through bastions, `ProxyJump`, and strict firewalls. mosh needs UDP ports
  60000–61000 open inbound, which locked-down environments rarely allow.
- **Minimal server requirements.** tmux or GNU Screen is preinstalled or one
  package away on nearly any host; `mosh-server` usually isn't.
- **The session outlives the client.** State lives in the multiplexer on the
  server, so it survives a client reboot — and you can reattach from a
  different machine entirely. A mosh session belongs to one client and cannot
  be reattached; that's why mosh is typically paired with tmux anyway.
- **Full SSH ecosystem**: port forwarding, agent forwarding, `~/.ssh/config`,
  `ControlMaster`. mosh has none of these, and no native scrollback.

Where mosh wins:

- **Seamless roaming.** An IP change or laptop sleep is invisible — no drop,
  no reconnect. ssh-workspace detects a dead connection in ~30 seconds and
  visibly reconnects.
- **Latency masking.** Predictive local echo makes typing feel instant on
  high-latency links; SSH round-trips every keystroke.

If you work on flaky high-latency links and control the server, mosh + tmux
is a fine stack. If you want persistence with nothing but sshd and a
multiplexer on the remote end, that's what this tool is for.
