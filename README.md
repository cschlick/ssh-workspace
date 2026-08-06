# ssh-workspace

[![CI](https://github.com/cschlick/ssh-workspace/actions/workflows/ci.yml/badge.svg)](https://github.com/cschlick/ssh-workspace/actions/workflows/ci.yml)

SSH into a host and attach to a persistent terminal-multiplexer session in one
command — [tmux](https://github.com/tmux/tmux) if the remote host has it,
[GNU Screen](https://www.gnu.org/software/screen/) otherwise. If the connection
drops, it reconnects automatically and your session picks up exactly where it
left off.

Useful for long-running work on remote machines — builds, training runs,
interactive sessions — where a flaky network or a closed laptop lid shouldn't
kill your shell.

## Install

The script itself is the whole tool — put it on your `PATH` and make it
executable. It needs only `bash` (the stock macOS 3.2 works) and `ssh`
locally; **remote hosts** need tmux or GNU Screen (`sudo apt install tmux`
on Debian/Ubuntu). Once installed, `ssh-workspace -U` updates it in place
from GitHub.

### macOS

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/cschlick/ssh-workspace/main/ssh-workspace \
    -o ~/.local/bin/ssh-workspace
chmod +x ~/.local/bin/ssh-workspace
```

If `~/.local/bin` isn't already on your `PATH`:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

Optional — a short `ws` alias and tab completion for zsh (the macOS default
shell):

```sh
mkdir -p ~/.zsh/completions
curl -fsSL https://raw.githubusercontent.com/cschlick/ssh-workspace/main/completions/_ssh-workspace \
    -o ~/.zsh/completions/_ssh-workspace
cat >> ~/.zshrc <<'EOF'
alias ws=ssh-workspace
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
EOF
```

(If your `~/.zshrc` already runs `compinit`, add the `fpath` line above it
instead of repeating `compinit`.)

### Linux

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/cschlick/ssh-workspace/main/ssh-workspace \
    -o ~/.local/bin/ssh-workspace
chmod +x ~/.local/bin/ssh-workspace
```

`~/.local/bin` is on the default `PATH` in most distributions; if not, add
the same `export PATH` line to `~/.bashrc`.

Optional — `ws` alias and bash tab completion:

```sh
mkdir -p ~/.local/share/bash-completion/completions
curl -fsSL https://raw.githubusercontent.com/cschlick/ssh-workspace/main/completions/ssh-workspace.bash \
    -o ~/.local/share/bash-completion/completions/ssh-workspace
echo 'alias ws=ssh-workspace' >> ~/.bashrc
```

(The `bash-completion` package auto-loads that directory. Without it,
`source` the file from `~/.bashrc` instead. On Linux with zsh, follow the
macOS zsh steps.)

Completion covers option flags, `-m` modes, and host names from
`~/.ssh/config`; it applies to the `ws` alias too, since shells expand
aliases before completing.

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

Each successful connection remembers where it went: run `ssh-workspace` with
no host at all and it reconnects straight to the last workspace (host,
session, port, and `-o` options included). Explicit flags override the saved
values; failed connection attempts never overwrite the saved workspace.

| Option | Description |
| ------ | ----------- |
| `-u USER` | SSH username |
| `-s SESSION` | Session name; skips the interactive picker |
| `-l` | List workspaces on the host and exit |
| `-U` | Self-update: fetch the latest from GitHub, show the source URL and destination path, and replace this script after confirmation |
| `-m MODE` | Multiplexer: `auto`, `tmux`, or `screen` (default: `auto` — tmux if available, else Screen) |
| `-p PORT` | SSH port (default: SSH config or 22) |
| `-i FILE` | SSH identity file |
| `-o OPTION` | Additional SSH option; may be repeated |
| `-e TERM` | Terminal type (default: `xterm-256color`) |
| `-c COMMAND` | Run COMMAND when the session is first created (ignored when attaching to an existing session; the session ends when it exits — append `; exec $SHELL` to drop to a shell afterwards) |
| `-n` | Do not reconnect automatically |
| `-h` | Show help |

Examples:

```sh
ssh-workspace picomol                          # attach to "workspace" on picomol
ssh-workspace root@picomol                     # as root
ssh-workspace -s claude root@picomol           # separate named session
ssh-workspace -m screen picomol                # force GNU Screen
ssh-workspace -l picomol                       # list workspaces, don't attach
ssh-workspace -s train -c 'cd ~/runs && python train.py' picomol
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
The last-workspace file lives in `~/.local/state/ssh-workspace/`; control
sockets live in `/tmp/ssh-workspace-<uid>/`, which is kept short because
unix socket paths cap at ~104 characters.

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

The terminal bell rings when a reconnect succeeds and when retries pause for
input, so a backgrounded tab gets a badge when your workspace comes back or
needs attention.

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
