#!/usr/bin/env bash
# Upload one file to Roblox through the Open Cloud Assets API and wait for its asset id.
#
# usage: open_cloud_upload.sh [--dry-run] <file> <Image|Audio|Model|Animation> "<display name>"
# prints: assetId=<id> assetType=<type> moderation=<state>
#
# Accepted extensions are only the ones this project has actually uploaded and seen accepted:
#   .png  -> Image        .mp3  -> Audio
#   .glb  -> Model        .rbxm -> Animation, or Model (Animation is the exercised one)
# Other formats Roblox may well accept (.jpg, .ogg, .fbx, .rbxmx, ...) are untested here and are
# refused on purpose, so a run cannot burn an upload on a server-side rejection. See the
# "Asset types and formats" table in references/asset-upload.md before adding one.
#
# Needs ROBLOX_API_KEY and ROBLOX_CREATOR_USER_ID in the environment (see references/asset-upload.md
# for the .env pattern). The key is never printed and never passed as a command argument: it goes to
# curl as a header on stdin, so it does not appear in the process table. --dry-run prints the request
# without sending it and needs no credentials. Dependencies: curl, python3.
#
# This personal-key script is a stopgap until the MCP exposes a publishing tool; see the
# "Forward compatibility" section of references/asset-upload.md.
set -euo pipefail

MAX_BYTES=20000000            # Roblox Open Cloud file limit reported in PR #1
POLL_SECONDS=3
POLL_ATTEMPTS=40              # 2 minutes
API=https://apis.roblox.com/assets/v1

usage() {
  echo "usage: $0 [--dry-run] <file> <Image|Audio|Model|Animation> \"<display name>\"" >&2
  echo "verified extensions: .png=Image .mp3=Audio .glb=Model .rbxm=Animation|Model" >&2
  exit 2
}

dry_run=0
args=()
for a in "$@"; do
  if [ "$a" = "--dry-run" ]; then dry_run=1; else args+=("$a"); fi
done
[ ${#args[@]} -eq 3 ] || usage
file=${args[0]}; type=${args[1]}; name=${args[2]}

[ -f "$file" ] || { echo "error: no such file: $file" >&2; exit 2; }

# Content type per extension, plus the asset types that extension is allowed to be uploaded as.
# The caller's asset type decides; this only refuses combinations we know are wrong or untested.
ext=$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')
case "$ext" in
  png)  ct=image/png;          ok="Image" ;;
  mp3)  ct=audio/mpeg;         ok="Audio" ;;
  glb)  ct=model/gltf-binary;  ok="Model" ;;
  rbxm) ct=model/x-rbxm;       ok="Animation Model" ;;
  *) echo "error: .$ext is not a verified format here (png mp3 glb rbxm); see references/asset-upload.md" >&2; exit 2 ;;
esac
case "$type" in Image|Audio|Model|Animation) ;; *) usage ;; esac
case " $ok " in *" $type "*) ;; *) echo "error: .$ext uploads as ${ok// / or }, not $type" >&2; exit 2 ;; esac
if [ "$ext" = "rbxm" ] && [ "$type" = "Model" ]; then
  echo "note: .rbxm as Model is allowed but was never exercised here; .rbxm was only verified as Animation" >&2
fi

size=$(wc -c < "$file" | tr -d ' ')
[ "$size" -le "$MAX_BYTES" ] || { echo "error: $file is $size bytes, over the $MAX_BYTES limit" >&2; exit 3; }

if [ "$dry_run" -eq 0 ]; then
  [ -n "${ROBLOX_API_KEY:-}" ] || { echo "error: ROBLOX_API_KEY is not set (see references/asset-upload.md)" >&2; exit 1; }
  [ -n "${ROBLOX_CREATOR_USER_ID:-}" ] || { echo "error: ROBLOX_CREATOR_USER_ID is not set (see references/asset-upload.md)" >&2; exit 1; }
fi

req=$(python3 -c 'import json,sys
print(json.dumps({"assetType": sys.argv[1], "displayName": sys.argv[2][:50],
  "description": "Uploaded by open_cloud_upload.sh",
  "creationContext": {"creator": {"userId": sys.argv[3]}}}))' \
  "$type" "$name" "${ROBLOX_CREATOR_USER_ID:-<ROBLOX_CREATOR_USER_ID>}")

if [ "$dry_run" -eq 1 ]; then
  echo "dry-run: POST $API/assets"
  echo "  file=$file bytes=$size contentType=$ct"
  echo "  request=$req"
  if [ -n "${ROBLOX_API_KEY:-}" ]; then key_state=set; else key_state=unset; fi
  echo "  header x-api-key: <ROBLOX_API_KEY is $key_state; never printed, sent on stdin>"
  echo "  then poll $API/operations/<id> every ${POLL_SECONDS}s, up to $POLL_ATTEMPTS times"
  exit 0
fi

# The key goes to curl as a header read from stdin, so it never lands in argv / the process table.
api_curl() { printf 'x-api-key: %s\n' "$ROBLOX_API_KEY" | curl -sS -H @- "$@"; }

resp=$(api_curl -m 120 -X POST "$API/assets" -F "request=$req" -F "fileContent=@$file;type=$ct")
op=$(printf '%s' "$resp" | python3 -c 'import json,sys
d=json.load(sys.stdin); print(d.get("path") or d.get("operationId") or "")' 2>/dev/null || true)
[ -n "$op" ] || { echo "error: upload rejected: $(printf '%s' "$resp" | head -c 400)" >&2; exit 4; }
op=${op#operations/}

# Classify one poll reply: "pending", "done ...", "failed ...", or "badreply ..." for a non-JSON
# body (an auth error page or HTML) — that must stop the loop, not silently burn the full timeout.
classify='import json,sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except ValueError:
    print("badreply " + " ".join(raw.split())[:300]); raise SystemExit(0)
if not isinstance(d, dict):
    print("badreply " + " ".join(raw.split())[:300]); raise SystemExit(0)
if "error" in d:
    print("failed " + json.dumps(d["error"])[:400]); raise SystemExit(0)
if not d.get("done"):
    print("pending"); raise SystemExit(0)
r = d.get("response") or {}
print("done assetId=%s assetType=%s moderation=%s" % (r.get("assetId"), r.get("assetType"),
      (r.get("moderationResult") or {}).get("moderationState")))'

i=0
while [ "$i" -lt "$POLL_ATTEMPTS" ]; do
  verdict=$(api_curl -m 30 "$API/operations/$op" | python3 -c "$classify")
  case "$verdict" in
    pending) ;;
    done\ *)     echo "${verdict#done }"; exit 0 ;;
    failed\ *)   echo "error: operation $op ${verdict#failed }" >&2; exit 5 ;;
    badreply\ *) echo "error: operation $op returned a non-JSON reply (auth error or HTML?): ${verdict#badreply }" >&2; exit 7 ;;
    *)           echo "error: unrecognised poll reply: $verdict" >&2; exit 7 ;;
  esac
  i=$((i + 1)); sleep "$POLL_SECONDS"
done
echo "error: operation $op not done after $((POLL_SECONDS * POLL_ATTEMPTS)) s; keep the id and re-check it, do not re-upload" >&2
exit 6
