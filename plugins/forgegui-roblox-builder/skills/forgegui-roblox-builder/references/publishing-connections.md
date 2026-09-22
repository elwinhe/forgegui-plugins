# Roblox publishing connections

The request examples match backend contract **1.9.0**, pinned in
`tests/backend-preparation-contract.json` at backend commit `7f21d40aeb556528f28d38c228282c1ea0eb5177`. This is local contract validation,
not deployment or Studio acceptance. Discover live schemas and account
capabilities before using a connection tool or field.

## Select before spending

1. Discover tools and call `asset_capabilities` (`generation:read`). For publication,
   when live advertised, call `publication_connections_list` (`publication:read`)
   and inspect every returned page if the live schema supplies pagination.
   Do not invent pagination arguments. Discovery is free; it does not authorize
   generation or select a destination.
2. Resolve the user's intended creator against the returned connections. Use an
   existing explicit decision when it unambiguously matches; otherwise ask before
   paid work. Never select the first connection or infer consent from discovery,
   a label, the current account, or a default. Show the selected label, safe
   `connection_id`, and creator `type` (`user` or `group`) and decimal-string `id`.
3. Check the exact route's live schema, account usability, supported asset type,
   active connection status and required scopes. A listed connection alone is
   insufficient. `needs_validation`, `expired`, `revoked`, `disabled`, foreign or
   missing connections, unsupported types, unavailable routes and missing scopes
   block dependent paid work. Report the safe unavailable reason; do not expose
   provider error bodies. Discovery is a snapshot: admission may still reject it.
4. Confirm an authorized access path in the intended experience before spending.
   Publication ownership, moderation, experience access and actual Studio use
   are separate checks. Preserve the selected identity and exact non-secret
   request in [ledger v2](project-manifest.md) before submission.

Roblox publishing keys go only through authenticated ForgeGUI settings. Never
request, receive, echo or store them in agent chat, MCP arguments, commands,
ledger, URLs or logs. The plugin consumes safe connection metadata only; it
does not introspect keys or choose credential slots. Rotation/disconnect also
belong in settings. The ForgeGUI account key configured in the client's masked
field is a separate credential. OAuth is unavailable for this release; account
linking is not publication authorization. Do not advertise unavailable routes.

Direct/omitted delivery requires no connection and never publishes. For work
requiring Roblox publication, missing discovery or selector support means the
connection route is unavailable. New publication requires an explicitly selected usable `connection_id`.
The legacy shared-group request shapes are replay-only for this backend, even
with explicit consent or stale capabilities advertising the shared route.
A verified manual handoff remains a separate choice before new work.
Never fall back to the shared group, another connection, local upload or a
different creator after failure. A future destination change is a new explicit
decision for new work; accepted operations retain their original destination.

## Request selectors (capability-gated)

| Operation | Selector and scopes |
| --- | --- |
| `generation_model_3d`, `generation_music`, `generation_sound_effect` | Optional `delivery: {"mode":"publish","platform":"roblox","connection_id":"00000000-0000-4000-8000-000000000010"}`; `generation:write` plus `publication:write`, `generation:read` for polling |
| Direct generation | Omit `delivery` or use `{"mode":"direct"}`; no connection or publication scope required |
| Existing owned Model/Image/Audio via `artifact_publish` | `destination: {"platform":"roblox","connection_id":"00000000-0000-4000-8000-000000000010"}`; `publication:write`, `publication:read` for polling |
| Replay-only legacy standalone publication | `destination: {"platform":"roblox","creator":"configured_shared_group"}` with the original request ID and arguments; no new submissions |
| Replay-only legacy integrated publication | Original `delivery: {"mode":"publish","platform":"roblox"}` with the original request ID and arguments; no new submissions |

The input schema retains replay compatibility; schema validity does not establish
new-work admission. Replay lookup precedes admission checks; without an accepted
matching operation, legacy publication returns `capability_unavailable` before
new work. Never submit a fresh legacy request to test whether it was accepted.

Standalone destination is a **strict union**: `connection_id` OR
`creator: configured_shared_group`, never both. No raw keys, arbitrary creator
overrides, `user_id`, `group_id`, or credential references are accepted selectors.
Do not add connection fields to direct requests, remesh, image generation,
preparation or GUI segmentation. No new image-generation delivery is proposed.
Publish an exact owned prepared member, not its source or an entire bundle.

Integrated music must request strictly less than 420 seconds; direct music keeps
its existing allowance (up to 600 seconds). Measured validation still applies.
Do not shorten, transcode, change delivery or regenerate automatically on rejection.

Save stable request IDs and exact arguments. Never add new defaults or connection
IDs to accepted legacy/direct requests. An explicitly supplied connection is part
of request identity: changing it under the same request ID conflicts. Replays
must retain the accepted operation and creator even if defaults, rollout or
connection availability later change. Never replay an ambiguous submission just
to obtain a missing status ID. Status reads use saved job/publication IDs, not
request IDs, and should remain readable after connection expiry. A denied read
is an access blocker, not evidence that the operation disappeared.

## Receipts and recovery

Keep the current public shapes; this feature does not migrate response envelopes:

- Integrated Model: `result: null`, one `delivery` projection with `status`,
  `publication_id`, decimal-string `asset_id`, `asset_type` and returned creator
  metadata. Preserve legacy `creator_group_id` if returned; do not fabricate it
  for a user creator. Poll `generation_status` until delivery is ready.
- Integrated audio: `result: null`, aggregate `delivery.status` plus indexed
  `delivery.outputs[]` receipts. Retain each output's index, optional artifact
  ref, publication ID, string asset ID, status, moderation and safe errors. Null
  IDs or missing members may mean recovery is pending. `partially_ready` and
  `incomplete` never make every output usable; preserve successes individually.
- Standalone: top-level `publication_id`, `status`, `asset_id`, `asset_type`,
  `creator: {type, id}`, moderation and safe errors. Poll `publication_status`.

Compare returned creator identity to the selected identity before insertion.
Mismatch or missing creator evidence blocks an ownership claim and insertion
until reconciled. Never overwrite the selection to make a receipt appear valid.
Never republish integrated outputs, including outputs with a missing publication
ID. Publication failure does not authorize new generation or a generation charge.
Keep retained artifacts and use only an explicitly supported publication-only
recovery action after reconciling the original state. Rotation, revocation or
disconnect never authorizes another Create Asset request or creator change.

The following caller action table is normative and checked offline. When several
conditions apply, use the most restrictive action; an ambiguous member blocks
writes for that member without discarding other ready receipts.

| Condition | Allowed next action | Forbidden actions |
| --- | --- | --- |
| direct | generate_direct | require_connection, publish |
| selected_active_usable_scoped | submit_selected | select_first, change_creator |
| selection_missing | ask_destination | paid_work, select_first |
| discovery_unavailable | report_unavailable | advertise_connection, paid_work, shared_fallback |
| connection_ineligible | report_unavailable | paid_work, shared_fallback, change_creator |
| type_or_route_unavailable | report_unavailable | paid_work, shared_fallback |
| scope_missing | report_scope | paid_work, broaden_scopes |
| credential_requested | settings_only | chat_key, mcp_key, command_key, ledger_key |
| legacy_new_request | report_unavailable | submit_legacy, paid_work, shared_fallback |
| legacy_accepted | read_original_or_reconcile | change_arguments, new_request_id, change_creator |
| integrated_pending | poll_original | standalone_publish, local_upload, regenerate |
| pending_moderation | poll_original | insert, regenerate |
| partial_audio | inspect_members | republish_ready, regenerate_batch, discard_receipts |
| ready_creator_matches | verify_access_and_studio | claim_verified_without_checks |
| creator_mismatch | reconcile_original | insert, change_creator, shared_fallback |
| failed | report_preserve_artifact | regenerate, shared_fallback |
| ambiguous | reconcile_original | resend, new_request_id, shared_fallback, local_upload, change_creator |
| unknown_state | reconcile_original | resend, insert |
| revoked_after_acceptance | read_original_or_reconcile | resend, change_creator, shared_fallback |

`ambiguous` includes `outcome_unknown`, `needs_reconciliation`, a lost response
and timeout without a definitive result. Preserve all IDs; query saved status
IDs with bounded backoff. If none exist, retain request/tool/arguments/time and
safe correlation evidence for operator reconciliation. Do not invent a lookup,
infer a refund or use a new request ID as an escape hatch. See
[upload recovery](asset-upload.md), [audio publication](audio-publication.md) and
[model installation](3d-assets.md) for the existing safety and verification steps.
An asset ID alone is not ready; verify access, saved Edit-mode insertion and
rendering/audible playback in the intended experience. Mark unperformed checks
`not_performed`. Preserve intentional holes/openings; do not repair geometry or
spend again merely because a topology diagnostic reports open edges.

## Contract validation and release boundary

[Connection fixtures](../../../../../tests/publishing-connections.json) cover
discovery, direct and connected Model/music/SFX generation, standalone
Model/Image/Audio publication, replay-only legacy delivery and partial audio receipts.
Request fixtures are validated against the pinned backend input schemas;
receipt examples and guidance assertions are not portable output schemas or
proof of installed-agent behavior.

Run `tests/test_publishing_connections.py` and `tests/test_preparation_contract.py`.
Set `FORGEGUI_BACKEND_CONTRACT` to the exact backend export to check its hash
and every pinned tool definition. Staging still requires dedicated user/group
credentials, actual uploads and recovery, followed by Studio insertion/playback
verification. Personal and group publication, rotation during pending work,
disconnect and interrupted-worker recovery remain unverified in hosted acceptance.
All unknown quota owners still share one bucket, the default global upload limit
is two, and a bucket-level 429 can pause that shared bucket. User-supplied keys
change ownership, not independent publishing capacity.
Installation of this package does not enable the backend gates.
