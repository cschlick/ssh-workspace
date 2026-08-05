#!/usr/bin/env bash
#
# Test suite for ssh-workspace. Substitutes a fake ssh on PATH and
# checks the commands the script would send; no network involved.
#
# Fake ssh knobs (environment variables):
#   ARGS           file to record the ssh arguments in
#   OUT            file to record the remote command of attach (-tt) calls
#   ATTACH_STATUS  exit status for attach calls (default 0)
#   LIST_STATUS    exit status for list calls (default: print a session list)
#   FLAKY          path; first attach fails with 255, later ones succeed

set -u

here=$(cd "$(dirname "$0")" && pwd)
sw="$here/../ssh-workspace"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export XDG_STATE_HOME="$tmp/state"
mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"

cat > "$tmp/bin/ssh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "${ARGS:-/dev/null}"
has_tt=0
for a in "$@"; do [[ "$a" == -tt ]] && has_tt=1; done
if [[ "$has_tt" == 1 ]]; then
    if [[ -n "${FLAKY:-}" && ! -e "$FLAKY" ]]; then
        : > "$FLAKY"
        exit 255
    fi
    printf '%s' "${@: -1}" > "${OUT:-/dev/null}"
    exit "${ATTACH_STATUS:-0}"
fi
[[ -z "${LIST_STATUS:-}" ]] || exit "$LIST_STATUS"
printf 'tmux\nattached workspace\ndetached build\n'
EOF
chmod +x "$tmp/bin/ssh"

pass=0
fail=0

check() {
    if [[ "$2" -eq 0 ]]; then
        pass=$((pass + 1))
        printf 'ok   %s\n' "$1"
    else
        fail=$((fail + 1))
        printf 'FAIL %s\n' "$1"
    fi
}

# Run a command on a pseudo-terminal, feeding it input, so the
# interactive picker is exercised. BSD and util-linux script(1)
# disagree on syntax.
run_pty() {
    local input="$1"
    shift
    case "$(uname)" in
        Darwin)
            { sleep 1; printf '%b' "$input"; sleep 1; } |
                script -q /dev/null "$@"
            ;;
        *)
            { sleep 1; printf '%b' "$input"; sleep 1; } |
                script -qec "$*" /dev/null
            ;;
    esac
}

# --- syntax ---------------------------------------------------------

bash -n "$sw"
check "script parses" $?

# --- remote command generation --------------------------------------

env OUT="$tmp/o" "$sw" testhost </dev/null >/dev/null
grep -q -- 'tmux new-session -A -D -s workspace$' "$tmp/o"
check "non-interactive run defaults to session 'workspace'" $?

env OUT="$tmp/o" "$sw" -s direct testhost </dev/null >/dev/null
grep -q -- '-s direct$' "$tmp/o"
check "-s sets the session name" $?

env OUT="$tmp/o" "$sw" -m screen testhost </dev/null >/dev/null
grep -q 'if false && command -v tmux' "$tmp/o" &&
    grep -q 'if true && command -v screen' "$tmp/o"
check "-m screen disables tmux" $?

env OUT="$tmp/o" "$sw" -c 'cd /work && make' testhost </dev/null >/dev/null
grep -q -- '-s workspace cd\\ /work\\ \\&\\&\\ make$' "$tmp/o" &&
    grep -q -- 'sh -c cd\\ /work' "$tmp/o"
check "-c passes a quoted startup command to both multiplexers" $?

# --- validation -----------------------------------------------------

"$sw" -m bogus testhost 2>/dev/null
check "-m rejects unknown modes" $(( $? == 2 ? 0 : 1 ))

"$sw" -s 'bad name' testhost 2>/dev/null
check "session names are validated" $(( $? == 2 ? 0 : 1 ))

"$sw" -s a.b testhost 2>/dev/null
check "dotted session rejected unless -m screen" $(( $? == 2 ? 0 : 1 ))

env OUT="$tmp/o" "$sw" -m screen -s a.b testhost </dev/null >/dev/null
check "dotted session allowed with -m screen" $?

"$sw" -c $'a\nb' testhost 2>/dev/null
check "-c rejects newlines" $(( $? == 2 ? 0 : 1 ))

# --- ssh invocation -------------------------------------------------

env ARGS="$tmp/a" OUT=/dev/null "$sw" -o ProxyJump=bastion testhost \
    </dev/null >/dev/null
user_line=$(grep -n 'ProxyJump=bastion' "$tmp/a" | cut -d: -f1)
default_line=$(grep -n 'ServerAliveInterval' "$tmp/a" | cut -d: -f1)
ordered=1
[[ -n "$user_line" && "$user_line" -lt "$default_line" ]] && ordered=0
check "user -o options precede defaults (first value wins)" "$ordered"

grep -q 'ControlMaster=auto' "$tmp/a"
check "connection sharing enabled" $?

# --- listing --------------------------------------------------------

out=$("$sw" -l testhost)
listed=1
[[ "$out" == 'Workspaces on testhost (tmux):
  workspace (attached)
  build (detached)' ]] && listed=0
check "-l lists workspaces" "$listed"

env LIST_STATUS=127 "$sw" -l testhost 2>/dev/null
check "-l exits 127 when no multiplexer" $(( $? == 127 ? 0 : 1 ))

# --- resume state ---------------------------------------------------

env OUT=/dev/null "$sw" -s alpha goodhost </dev/null >/dev/null
grep -q 'target=goodhost' "$XDG_STATE_HOME/ssh-workspace/last"
check "successful session saves resume state" $?

env ATTACH_STATUS=255 "$sw" -s bad typohost </dev/null >/dev/null 2>&1
grep -q 'target=goodhost' "$XDG_STATE_HOME/ssh-workspace/last"
check "failed connections do not overwrite resume state" $?

env ARGS="$tmp/a" OUT="$tmp/o" "$sw" </dev/null >/dev/null
grep -q 'goodhost' "$tmp/a" && grep -q -- '-s alpha$' "$tmp/o"
check "bare invocation resumes last workspace" $?

# --- reconnect ------------------------------------------------------

env FLAKY="$tmp/flaky" OUT="$tmp/o" "$sw" -s r rhost </dev/null >/dev/null
grep -q "printf '\\\\a' >&2" "$tmp/o"
check "reconnect attempts ring the bell on re-attach" $?

# --- interactive picker (needs a pty) -------------------------------

if command -v script >/dev/null 2>&1; then
    run_pty '2\n' env OUT="$tmp/o" "$sw" pickhost >/dev/null
    grep -q -- '-s build$' "$tmp/o"
    check "picker: number selects an existing session" $?

    run_pty 'newname\n' env OUT="$tmp/o" "$sw" pickhost >/dev/null
    grep -q -- '-s newname$' "$tmp/o"
    check "picker: typed name creates a session" $?

    run_pty '\n' env OUT="$tmp/o" "$sw" pickhost >/dev/null
    grep -q -- '-s workspace$' "$tmp/o"
    check "picker: Enter picks the first session" $?
else
    printf 'skip picker tests: script(1) not available\n'
fi

# --------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
