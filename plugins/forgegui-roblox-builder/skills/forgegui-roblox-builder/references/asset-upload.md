# Publishing assets and recovering interrupted uploads

Discover deployed ForgeGUI publishing tools first. Prefer ForgeGUI when its live schema and
permissions support **both the requested asset and destination owner**. Persist the caller's
request ID before submission; persist job/publication IDs and the asset ID as soon as returned. A timeout or
`outcome_unknown` requires status lookup and reconciliation using those identifiers. Never
switch routes or create a new request to resolve an ambiguous publication.

Open Cloud is an **explicitly chosen fallback**, after checking the intended owner and route.
It is not an automatic response to a ForgeGUI failure. The Python implementation below is
also the sole implementation behind the compatibility shell entry point.

## Credentials and destination

Supply `ROBLOX_API_KEY` through the process environment using a trusted secret manager or
masked shell input. Never put the key in arguments, logs, receipts, or checked-in files.
No `.env` is loaded. Choose exactly one explicit `--user-id` or `--group-id`; no account is
assumed. There is no credential command-line flag.

Before asset requests, the uploader uses Roblox's documented
[API key introspection](https://create.roblox.com/docs/cloud/auth/api-keys):
`POST https://apis.roblox.com/api-keys/v1/introspect` with JSON `apiKey`.
It requires `enabled: true`, `expired: false`, and destination-scoped `asset` read/write
operations. Personal uploads additionally require `authorizedUserId` to equal the destination,
including when `userIds` contains `*`. Group uploads require explicit matching `groupIds` for
both operations. A group wildcard alone cannot prove that user's authority for the requested
group, so this helper refuses it. No undocumented membership endpoint is assumed.

The [Assets usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets) documents
`creationContext.creator.userId` or `groupId`. Authority preflight is not a guarantee that
Roblox will accept an asset or grant the target experience access.

## Commands (run from the skill directory)

```sh
python3 references/tools/oc_upload.py model.glb --type Model --name "Prop" \
  --user-id 123456 --receipt prop-upload.json
# Same files, ordering, destination and metadata; polls saved operations or returns saved IDs:
python3 references/tools/oc_upload.py model.glb --type Model --name "Prop" \
  --user-id 123456 --receipt prop-upload.json --resume

scripts/open_cloud_upload.sh --dry-run chime.mp3 Audio "Chime" \
  --group-id 654321 --receipt chime-upload.json
scripts/open_cloud_upload.sh chime.mp3 Audio "Chime" \
  --group-id 654321 --receipt chime-upload.json
scripts/open_cloud_upload.sh chime.mp3 Audio "Chime" \
  --group-id 654321 --receipt chime-upload.json --resume

python3 references/tools/oc_upload.py art/*.png --type Image \
  --user-id 123456 --receipt images-upload.json
# Resume with the identical expanded file list:
python3 references/tools/oc_upload.py art/*.png --type Image \
  --user-id 123456 --receipt images-upload.json --resume
```

Replace example destination IDs with the intended owner. Dry-run validates local inputs only,
uses no network or credentials, and creates no receipt. The former optional `--json` export
is replaced by the mandatory durable receipt; downstream consumers can read succeeded entries.

## Recovery contract

Keep the receipt and its `.lock` file on a durable local filesystem supporting `flock`, atomic
rename and `fsync` (Linux/macOS). Do not delete, edit, relocate, or replace a receipt to retry.
Use the same receipt for the same publication; a new receipt represents a new publication,
not global deduplication. Do not run concurrent publishers using different receipt paths.

The receipt records canonical file paths, byte sizes, SHA-256 hashes, destination, type and
name. The bytes hashed are the bytes submitted. Input, owner or metadata drift is refused on
resume. An exclusive lock prevents concurrent writers to the same receipt. Writes use a
private temporary file, file fsync, atomic replacement and directory fsync.

States are `ready` → `submitting` → `polling` → `succeeded`. Intent is durable before POST,
the returned operation before polling, and each ID before the next upload. A failed second
file preserves the first file's success. No asset POST is automatically retried, even on
HTTP rejection. A crash, lost response or malformed response can leave `submitting`:
**this is ambiguous and blocks further submission**. Reconcile through Roblox's asset records
or support; retain this receipt and do not create a replacement to retry. This helper has no
manual override for ambiguous submissions. A crash before submission can conservatively
produce the same blocked state.

`--resume` polls `polling` entries without POST, replays `succeeded` IDs, and may submit only
previously untouched `ready` entries. Poll failures/timeouts keep the operation for a later
resume. Completed failures require reconciliation, not a new upload. Receipts contain no
credential or raw API response. API errors are deliberately sanitized; redirects and arbitrary
operation URLs are refused.

## Formats and readiness

Local preflight accepts PNG as Image, GLB as Model, MP3 as Audio, and RBXM as
Animation or Model, up to 20,000,000 bytes. Extension/type checks do not validate file contents.
Historical project uploads exercised PNG, GLB, MP3 and RBXM Animation. RBXM as Model is
accepted but unexercised. Both entry points conservatively refuse other formats, including
JPG/JPEG, FBX and OGG; this is a local compatibility restriction, not a claim that Roblox
rejects those formats. Inspect mesh limits before publication.

An **asset ID is not moderation approval or Studio usability**. The helper reports moderation
as unverified. Re-read moderation through the exposed asset lookup and verify insertion,
rendering/playback and access in the intended experience. Personal-account playback evidence
does not establish access for another account or group. Record route, owner, ID, moderation
and Studio verification separately in the asset ledger.
