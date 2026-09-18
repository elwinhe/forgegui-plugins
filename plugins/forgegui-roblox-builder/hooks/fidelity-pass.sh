#!/usr/bin/env bash
# Stop hook: reminds the agent of an opted-in fidelity pass and hands it over when the build is ready.
# A reminder and recovery aid, not a guarantee: the agent still decides, and asks the user before spending.
# Read-only. The agent owns the state; this hook never writes to the user's project.
#
# State lives in ./.forgegui-fidelity, one word: opted_in | ready | running | done.
# No file (the usual case) means no fidelity pass, and this hook does nothing.
input=$(cat)
state_file="${PWD}/.forgegui-fidelity"
prompt="${CLAUDE_PLUGIN_ROOT}/skills/forgegui-roblox-builder/references/fidelity-pass.md"
[ -r "$state_file" ] || exit 0
read -r state < "$state_file"   # no `||`: read reports failure at EOF, but a file without a trailing newline still holds a value
state=${state%$'\r'}            # a Windows editor may leave CRLF

# A continuing stop means this hook already spoke in this chain; never block twice in a row.
printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

case "$state" in
  ready)
    body=$(cat "$prompt" 2>/dev/null)
    [ -n "$body" ] || exit 0   # broken install: fail open rather than block the user's turn
    printf '%s\n' "$body" >&2
    exit 2
    ;;
  opted_in)
    echo "This project asks for a fidelity pass (.forgegui-fidelity says opted_in). Once the build is verified, write \"ready\" to that file and run the pass in $prompt yourself — do not wait for another stop to hand it to you. If you are waiting for the user's reply, end your turn." >&2
    exit 2
    ;;
  running)
    echo "A fidelity pass is marked running in .forgegui-fidelity. If it stalled (an interrupted or crashed session), resume it from $prompt and write \"done\" when it is verified. If you are mid-pass and waiting on the user, end your turn." >&2
    exit 2
    ;;
esac
exit 0
