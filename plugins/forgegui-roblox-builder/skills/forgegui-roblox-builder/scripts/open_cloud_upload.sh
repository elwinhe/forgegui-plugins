#!/usr/bin/env bash
# Upload one file to Roblox through the Open Cloud Assets API and wait for its asset id.
#
# usage: open_cloud_upload.sh [--dry-run] <file> <Image|Audio|Model|Animation> "<display name>"
# prints: assetId=<id> assetType=<type> moderation=<state>
#
# Needs ROBLOX_API_KEY and ROBLOX_CREATOR_USER_ID in the environment (see references/asset-upload.md
# for the .env pattern). The key is never printed. --dry-run prints the request without sending it
# and needs no credentials. Dependencies: curl, python3.
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
  exit 2
}

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then dry_run=1; shift; fi
[ $# -eq 3 ] || usage
file=$1; type=$2; name=$3

[ -f "$file" ] || { echo "error: no such file: $file" >&2; exit 2; }

# Content type and the asset type it belongs to, by extension.
ext=$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')
case "$ext" in
  png)        ct=image/png;          want=Image ;;
  jpg|jpeg)   ct=image/jpeg;         want=Image ;;
  mp3)        ct=audio/mpeg;         want=Audio ;;
  ogg)        ct=audio/ogg;          want=Audio ;;
  wav)        ct=audio/wav;          want=Audio ;;
  flac)       ct=audio/flac;         want=Audio ;;
  glb)        ct=model/gltf-binary;  want=Model ;;
  fbx)        ct=model/fbx;          want=Model ;;
  rbxm|rbxmx) ct=model/x-rbxm;       want=Animation ;;
  *) echo "error: unsupported extension .$ext (png jpg mp3 ogg wav flac glb fbx rbxm rbxmx)" >&2; exit 2 ;;
esac
case "$type" in Image|Audio|Model|Animation) ;; *) usage ;; esac
[ "$type" = "$want" ] || { echo "error: .$ext uploads as $want, not $type" >&2; exit 2; }

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
  echo "  header x-api-key: <ROBLOX_API_KEY is $key_state; never printed>"
  echo "  then poll $API/operations/<id> every ${POLL_SECONDS}s, up to $POLL_ATTEMPTS times"
  exit 0
fi

resp=$(curl -sS -m 120 -X POST "$API/assets" -H "x-api-key: $ROBLOX_API_KEY" \
  -F "request=$req" -F "fileContent=@$file;type=$ct")
op=$(printf '%s' "$resp" | python3 -c 'import json,sys
d=json.load(sys.stdin); print(d.get("path") or d.get("operationId") or "")' 2>/dev/null || true)
[ -n "$op" ] || { echo "error: upload rejected: $(printf '%s' "$resp" | head -c 400)" >&2; exit 4; }
op=${op#operations/}

i=0
while [ "$i" -lt "$POLL_ATTEMPTS" ]; do
  r=$(curl -sS -m 30 "$API/operations/$op" -H "x-api-key: $ROBLOX_API_KEY")
  if printf '%s' "$r" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("done") else 1)'; then
    printf '%s' "$r" | python3 -c 'import json,sys
d=json.load(sys.stdin)
if "error" in d:
    print("error: " + json.dumps(d["error"])[:400], file=sys.stderr); sys.exit(5)
r=d.get("response", {})
print("assetId=%s assetType=%s moderation=%s" % (r.get("assetId"), r.get("assetType"),
      (r.get("moderationResult") or {}).get("moderationState")))'
    exit $?
  fi
  i=$((i + 1)); sleep "$POLL_SECONDS"
done
echo "error: operation $op not done after $((POLL_SECONDS * POLL_ATTEMPTS)) s; keep the id and re-check it, do not re-upload" >&2
exit 6
