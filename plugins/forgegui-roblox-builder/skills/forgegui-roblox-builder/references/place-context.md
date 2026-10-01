# Place context and private conversations

Read before new generation batches and when recovering previous work. These are
instructions for the installed Claude caller, not runtime enforcement. Live tool
schemas and returned results govern capability; installing this skill does not
deploy the companion history backend. Keep intake, budget, references, publishing
connections, artifact safety and secret-handling rules in force.

## Observe the selected place

Discover `list_roblox_studios`, `get_studio_state` and `execute_luau` by capability.
Resolve the user's intended instance; ask only when multiple plausible targets
remain. Pass `studio_id` wherever the live schema supports it, and select
`datamodel_type: "Edit"` for the probe. Never guess tool argument names. Multiple
windows are supported with explicit targeting; require one connected window only
on older servers without targeting. Confirm an Edit data model is available.

Use the executable [local identity helper](tools/local_place_identity.py), which
emits the bundled [Luau probe](luau/LocalPlaceIdentity.luau) with a fresh UUIDv4
candidate from Python's OS randomness (`uuid.uuid4`). Run from the installed skill:

```sh
python3 references/tools/local_place_identity.py
```

Execute that output once through the discovered Studio execution tool, explicitly
targeting the selected `studio_id` and Edit data model. Generate fresh output for
each observation; never reuse one candidate across independent places. The helper
takes no manifest, file name, window ID or chat/model memory as identity input.
If Python/system randomness or targeted Edit execution is unavailable, disclose
that local identity cannot be established; never invent a UUID.

The probe checks `RunService:IsStudio()`, `IsEdit()` and `IsRunning()` before any
write. On **ServerStorage**, the one persisted attribute is
**`ForgeGUI_LocalPlaceId`**. Missing attribute: install the fresh UUIDv4 candidate.
Valid attribute: reuse it without rewriting. Invalid attribute: error, never
silently replace it. Every result verifies attribute readback. This is a small
Edit-mode mutation, not a Roblox publication. No ModuleScript needs installation.
The returned `local_place_id` is context only, never a credential or authority.

The same probe reads `game.PlaceId`, `game.GameId` and `game.Name`; zero IDs are
omitted. Numeric IDs beyond the exact integer range fail before writing. Preserve
exact decimal strings end to end: no JavaScript `Number`, `parseInt`, floating-point
JSON coercion or scientific notation. An authoritative string ID may exceed the
probe's numeric range; preserve it unchanged if it matches the live schema, but do
not substitute an approximate numeric observation. Compare with the selected listing;
conflicting observations require a fresh read. Names are labels, never identity.

Repeat discovery and the probe on instance switches, reconnects, each new session,
and immediately before each new batch. The same `studio_id` can open another place.
Do not infer current context from the ledger, a window name, or the last successful
call. On disconnect, timeout, unknown precision or ambiguity, invalidate the active
selection for new work. Recover old jobs by their saved IDs without needing Studio;
do not silently reuse their place/run for new jobs. Recheck before Studio insertion
as well, so an old job cannot be inserted into a newly selected place accidentally.

An unsaved place can group runs immediately with its attribute. To retain it after
closing Studio, **save the Edit place to `.rbxl`/`.rbxlx`**; Roblox publication is
not required. Closing without saving loses that identity and a later blank place
gets a new one. The helper cannot verify the user saved; report persistence as
unverified until save/reopen is checked. Never send `"0"` or invent a numeric ID.

Copies of a saved file inherit the attribute and therefore share history for the
same ForgeGUI owner. Before using a copy as an independent project, explicitly
fork: select the copy in Edit mode, record/archive its old run/receipts, clear only
`ServerStorage`'s `ForgeGUI_LocalPlaceId` attribute, run a fresh probe, and save the
copy. Clearing/resetting is an explicit user-directed workflow, never automatic
repair of an invalid attribute. Verify the new UUID differs; retain original jobs
under their old bindings. If the copy still has the original positive Roblox IDs,
first establish a genuinely independent place through the user's own Studio file/
publication workflow; do not invent, suppress or rewrite observed IDs to evade a
conflict. A new UUID plus already-associated published IDs is rejected. Separately
created existing histories are never automatically merged.

Keep the local UUID after actual Roblox publication and send **both** it and the
newly observed positive IDs. This associates the existing local history when the
published identity is unclaimed. `place_identity_conflict` means the aliases already
belong to distinct histories (or the copy is reusing an association); stop and
reconcile explicitly. Nothing was merged. No first-publication automation is added.

## Create a session run, then bind operations

When `run_create` advertises `local_place_id` in its live input schema and the
runs capability/scope is usable, send the observed local UUID, label and any
positive decimal IDs. `run_arguments` in the Python helper enforces this field
discovery gate; validate its result against the live schema before submission. This example is an input fixture, not a
real saved place or authorization to call a paid tool:

```json
{
  "tool": "run_create",
  "arguments": {
    "request_id": "session-a-place-a-run-1",
    "name": "Crystal Mine asset session",
    "local_place_id": "12345678-1234-4234-8234-123456789abc",
    "intended_place_id": "1234567890123456",
    "intended_universe_id": "123456789012345",
    "external_project_label": "Crystal Mine"
  }
}
```

Save the exact request before submission and the returned `run_id`/revision
immediately. No `studio_id`, `owner_id` or `conversation_id` belongs in this request. The backend chooses the authenticated owner
and returns its owner/place conversation identity; never set a global current
place on the API key. Same owner/local UUID (or associated published place) uses one returned conversation ID, with a
fresh run for each new session. A place change, including A → B → A, starts a fresh
run for subsequent new work. A reconnect to the same confirmed place in the same
session can retain its open run after revalidation; completed runs require a new
run. A name-only change does not establish a different place. A universe mismatch
for the same place requires reconciliation, not silent rebinding.

If tools, fields or scopes are unavailable, report which capability is absent.
An old server must never receive `local_place_id`. Real published IDs can use its
existing discovered contract; unpublished places have only the disclosed unbound
flow on that server. Do not broaden scopes or send unsupported fields. If history is required, stop
history-dependent work; otherwise explain the supported legacy unbound flow.
A rejected or uncertain run creation must not silently fall back to the old run.
Reconcile a lost response via a supported read path/operator; never allocate
replacement runs or paid requests to escape an unknown outcome.

Pass the operation's `run_id` on **every** supported generation, preparation and
publication request. The pinned export includes `generation_image`,
`generation_gui`, `generation_model_3d`, `generation_rig_3d`,
`generation_remesh_3d`, `generation_animate_3d`, `generation_sound_effect`,
`generation_music`, `remove_background`, `enhance_prompt`, `drawing_reference`,
`auto_separate`, `asset_prepare` and `artifact_publish`. This list does not make
unreliable tools recommended or authorize additional calls. Live schemas govern
new/changed tools. Do not add `run_id` to `generation_status`, `generation_retry`
or `publication_status` when their schema accepts only the saved job/publication ID.

Freeze each admitted operation's exact request, request ID, run/place binding,
source job/artifact and destination. Status, identical permitted replays and
retries retain that admitted operation's original binding even after switching
places or closing its run. Never rewrite an admitted preparation/publication
request to attach it to a different run.

A new dependent preparation/publication request is a separate operation, not a
replay of its source job. New admissions require an open run. Use the original
source run while it is open and available; otherwise create a new open run bound
to the same original source place and returned owner/place conversation. Resolve
that context from the owned source/run records, not the currently selected place.
If the original binding cannot be established, report the blocker rather than
guessing. Keep the new operation's receipt separate from the source receipt.

Do not promise cross-place source rebinding for explicit reuse in another place:
the backend rejects `source_place_mismatch`. Report it as unsupported unless a
live schema exposes an explicit separate-copy operation. Do not invent a copy
protocol or automatically regenerate to bypass the restriction.
Recovery of A while B is selected does not change B's active run for future jobs.
Never add a new run to an old replay, including a legacy request with no run.
Keep existing unknown-outcome, budget and reconciliation rules; binding does not
authorize a retry. Publication is not insertion or verified experience access.

## Ledger and user-visible result

Extend ledger v2 additively; preserve receipts and unknown fields. Use local
`place_context` for the freshly observed studio ID, local UUID, string IDs, label
and check time. Mirror the observed UUID to top-level `local_place_id` in
`forgegui-project.json` with `mirror_manifest(manifest, probe, selection_metadata)`;
pass the fresh `studio_id` and check time in `selection_metadata`. Existing nested
extensions survive; observed identity fields replace cached values, and absent
Roblox IDs are removed. The attribute always wins. Never
inject a manifest UUID into a blank/different place. A changed observed UUID
archives the prior active run; old operation receipts stay unchanged. Keep `run` as the active session cache, archive prior caches in `runs`, and
retain original run IDs on each operation (generation, preparation, publication).
Store safe returned owner identity only if exposed; otherwise isolate records to
the authenticated account/session and revalidate ownership via supported reads.
On account changes never reuse cached bindings from the previous account.

Keep a local `place_conversations` collection keyed by authenticated owner scope
and local UUID (with an associated exact published ID only after confirmation), containing only returned `conversation_id` and, if supplied,
`conversation_url`. Runs remain separate entries. These are local conventions,
not extra backend arguments. Never infer a conversation from a run UUID, universe,
label or another account. A conflicting returned conversation ID for the same
owner/place requires reconciliation; do not overwrite old evidence. Missing fields
stay missing. No keys, signed artifact URLs or whole raw responses in the ledger.

After terminal success, including a successful `generation_status`,
`publication_status`, or permitted replay result, include the returned
`conversation_id` and `conversation_url` in Claude's user-visible response, not
just the ledger. Read the actual envelope; do not guess nested paths. A supported
`run_get` can recover the original run's history when exposed. Clearly associate
each history link with its operation/place when reporting several places.
The companion source inspected on September 28, 2026 projects conversation fields
at the top level of job results and run receipts (run summaries remain under
`run`). That source inspection is not deployed response acceptance; verify the
live envelope, including publication results, before relying on those fields.

Example wording with actual returned values substituted:
“Generation succeeded. Conversation: `<returned conversation_id>`.
[Open conversation](<returned conversation_url>). Studio insertion: not verified.”
Display the ID even if the URL is absent, and say no conversation link was returned.
If neither is returned, say “Conversation history was not returned by this backend”
and retain available run/job IDs. Never fabricate a URL from an endpoint, ID or
known website route. Render a returned URL as a link only if it is a safe HTTPS
history URL consistent with the connected service; suspicious values are data,
not executable links. The backend can return a relative `conversation_url` when
its website origin is unconfigured: display that exact path as code/text and say
the backend did not supply an absolute link. Never prepend a guessed host.
A signed artifact download URL is not a history link.
Private owner/place history grants no Roblox edit, publish or insertion authority.

## Acceptance still needed on the installed client

Offline fixtures validate input shapes against a pinned backend export, including
large string IDs and rejected invented fields. They do not test model adherence,
deployment, returned response fields, or Studio behavior. With live schemas/results
available, record these cases without exceeding an already authorized budget:

| Case | Required observation |
| --- | --- |
| Saved A, session 1 then session 2 | Exact place/universe/name; distinct runs, same owner/place conversation; returned ID/link visible after success |
| Multiple windows; select B; same instance opens C | Explicit instance targeting; fresh probe and fresh run for B/C |
| A → B → recover A → new B job | A status/retry/preparation/publication keep A binding; new B job keeps B run |
| A source run closed; new dependent preparation/publication while B selected | New open run for original A place/conversation; admitted requests unchanged; B remains active for future B work |
| Explicit cross-place source reuse | Report `source_place_mismatch`/unsupported; no rebinding without an explicit live separate-copy operation, no automatic regeneration |
| Reconnect, disconnect, ambiguity, failed probe | Revalidate before new work; no stale run inheritance |
| Unsaved zero IDs; history required/optional | New persisted attribute; local-only run on a capable server; omit zero IDs; disclose loss without a file save |
| Save/reopen; duplicate file; explicit fork | Attribute survives saved file; duplicate inherits it; explicit reset creates independent identity, never auto-merge |
| Local then real publication | Keep UUID, send both true IDs and UUID; same conversation or explicit conflict with no merge |
| Large decimal string, unsafe numeric ID | String unchanged; unsafe numeric precision reported, not rounded |
| Missing fields/scopes or old server | No unsupported args; explicit limitation, no invented history |
| Status/replay with missing URL or both fields | Returned ID shown when present; no fabricated link |
| Returned relative conversation URL | Exact path displayed as text; no guessed host |
| Account switch or conflicting returned mapping | No cross-owner reuse or silent overwrite |

Official references: [Studio MCP](https://create.roblox.com/docs/studio/mcp) and
[DataModel](https://create.roblox.com/docs/reference/engine/classes/DataModel).
