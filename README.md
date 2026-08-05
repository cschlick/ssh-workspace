# ssh-workspace

SSH into a host and attach to a persistent [GNU Screen](https://www.gnu.org/software/screen/)
session in one command. If the connection drops, it reconnects automatically and
your session picks up exactly where it left off.

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

Requirements: `bash` and `ssh` locally, GNU Screen on the remote host
(`sudo apt install screen` on Debian/Ubuntu).

## Usage

```
ssh-workspace [options] HOST
ssh-workspace [options] USER@HOST
```

| Option | Description |
| ------ | ----------- |
| `-u USER` | SSH username |
| `-s SESSION` | Screen session name (default: `workspace`) |
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
ssh-workspace -p 2222 -s admin alice@example.com
ssh-workspace -o ProxyJump=bastion root@internal-server
```

Running the same command from another machine steals the session
(`screen -D -RR`), so you can walk from desktop to laptop and reattach to the
same shell.

Detach with `Ctrl-A d`, or exit the remote shell to end the session.

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
