#!/usr/bin/env bash
# Compatibility: [--dry-run] FILE TYPE NAME --user-id ID|--group-id ID --receipt PATH [--resume]
set -euo pipefail
flags=()
if [[ ${1:-} == --dry-run ]]; then flags+=(--dry-run); shift; fi
if [[ $# -lt 3 ]]; then
  echo 'usage: open_cloud_upload.sh [--dry-run] FILE TYPE NAME --user-id ID|--group-id ID --receipt PATH [--resume]' >&2
  exit 2
fi
file=$1; type=$2; name=$3
shift 3
exec python3 "$(dirname "${BASH_SOURCE[0]}")/../references/tools/oc_upload.py" \
  "${flags[@]}" --type "$type" --name "$name" "$@" -- "$file"
