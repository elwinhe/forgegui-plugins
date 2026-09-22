#!/usr/bin/env bash
# Self-check for plugins/forgegui-roblox-builder/hooks/fidelity-pass.sh. Run: bash tests/fidelity-pass-hook.sh
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$root/plugins/forgegui-roblox-builder"
hook="$plugin/hooks/fidelity-pass.sh"
prompt_rel="skills/forgegui-roblox-builder/references/fidelity-pass.md"
work="$(mktemp -d)"; trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
fail=0

run() { # run <stdin-json> [plugin-root]; sets code and err
  err="$(cd "$work" && CLAUDE_PLUGIN_ROOT="${2:-$plugin}" printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="${2:-$plugin}" bash "$hook" 2>&1 >/dev/null)"; code=$?
}
expect() { # expect <label> <want-code> [substring]
  if [ "$code" != "$2" ] || { [ -n "${3:-}" ] && [[ "$err" != *"$3"* ]]; }; then
    echo "FAIL $1 (code $code, want $2)"; fail=1; else echo "ok   $1"; fi
}
state() { printf '%s\n' "$1" > "$work/.forgegui-fidelity"; }
state_is() { # state_is <label> <want>
  got="$(cat "$work/.forgegui-fidelity" 2>/dev/null)"
  [ "$got" = "$2" ] && echo "ok   $1" || { echo "FAIL $1 (state '$got', want '$2')"; fail=1; }
}
stop='{"session_id":"t","stop_hook_active":false}'
again='{"session_id":"t","stop_hook_active": true}'

# states
rm -f "$work/.forgegui-fidelity"; run "$stop"; expect "no state file allows stop" 0
state off;      run "$stop"; expect "off allows stop" 0
state done;     run "$stop"; expect "done allows stop" 0
state running;  run "$stop"; expect "running offers to resume an interrupted pass" 2 "resume it"
state running;  run "$again"; expect "running continuing stop is allowed" 0
state opted_in; run "$stop"; expect "opted_in reminds, naming the file" 2 ".forgegui-fidelity"
                             expect "opted_in points at the pass file, not another stop" 2 "fidelity-pass.md"
state ready;    run "$stop"; expect "ready injects the fidelity block" 2 "Compare the game directly against the reference"
                             expect "ready injection names its source" 2 "ForgeGUI plugin's Stop hook"

# loop guards: a continuing stop must never block again (both branches)
state opted_in; run "$again"; expect "opted_in continuing stop is allowed" 0
state ready;    run "$again"; expect "ready continuing stop is allowed" 0

# the hook is read-only: it must never write to the user's project
state ready; before="$(cat "$work/.forgegui-fidelity")"; run "$stop"
state_is "ready is left for the agent to change" "$before"
[ "$(ls -A "$work" | wc -l | tr -d ' ')" = "1" ] && echo "ok   no files created in the project" || { echo "FAIL hook created files"; fail=1; }

# broken install must fail open, never block the turn with a cat error
state ready; run "$stop" "/nonexistent-plugin-root"; expect "missing prompt file allows stop" 0
state_is "missing prompt leaves state untouched" "ready"
empty="$(mktemp -d)"; mkdir -p "$empty/$(dirname "$prompt_rel")"; : > "$empty/$prompt_rel"
state ready; run "$stop" "$empty"; expect "empty prompt file allows stop" 0; rm -rf "$empty"

# a read-only project must still work (this is where the old version looped forever)
state ready; chmod a-w "$work"; run "$stop"; expect "read-only project still injects" 2 "Compare the game directly"
run "$again"; expect "read-only project does not loop" 0; chmod u+w "$work"

# tolerate whatever the agent writes
printf 'ready' > "$work/.forgegui-fidelity";        run "$stop"; expect "no trailing newline still injects" 2 "Compare the game directly"
printf 'opted_in' > "$work/.forgegui-fidelity";     run "$stop"; expect "no trailing newline still reminds" 2 "fidelity-pass.md"
printf 'ready\r\n' > "$work/.forgegui-fidelity";    run "$stop"; expect "CRLF is fine" 2 "fidelity"
printf 'garbage\n' > "$work/.forgegui-fidelity";    run "$stop"; expect "unknown state allows stop" 0
: > "$work/.forgegui-fidelity";                     run "$stop"; expect "empty state file allows stop" 0

exit $fail
