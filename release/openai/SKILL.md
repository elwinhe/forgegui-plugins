---
name: forgegui-roblox-builder
description: Discover, generate, prepare and publish ForgeGUI Roblox assets through remote MCP, with bounded paid authorization and a handoff ledger. When local Roblox Studio tools are available, also install assets and verify the experience. Use for models, GUI art, images, audio and asset reuse.
---

# ForgeGUI for ChatGPT and Codex

This is a staging beta preview. Production service and OpenAI OAuth readiness
are unverified. Installing this package does not establish authentication,
publication access, Studio connectivity or successful import.

## Choose the runtime before planning

Discover exposed tools and their live schemas by capability. Do not infer local
Studio, filesystem, shell, network download or image inspection access from the
client name. A failed or missing ForgeGUI connection is a connection blocker;
do not diagnose Claude user configuration, substitute an endpoint, or request
keys in chat. Authentication belongs in the host's secure connection flow.
Never put credentials in MCP arguments, command lines, artifacts or the ledger.

The shared [WORKFLOW.md](WORKFLOW.md) and its references are copied from the
Claude source without edits. Read the applicable sections below before acting.
This runtime routing governs their applicability on OpenAI; Claude setup,
slash commands and hook mechanisms are not instructions for this runtime.

### Remote-only ChatGPT or Codex

Without local Studio tools, allow only supported remote ForgeGUI discovery,
generation, status, preparation and publication, followed by explicit handoff.
Read WORKFLOW sections 0, 2, 3, 4 and 5 for intake, authorization, references,
publication and job safety. Do not apply the mandatory Studio preflight in
section 1 or Studio editing, insertion, testing and visual-pass steps in
sections 6 and 7. Studio is not a prerequisite for remote discovery or an
explicitly requested downloadable asset. For a request to build inside Studio,
explain that installation is a handoff; settle that delivery scope before paid
work. Do not silently spend toward a Studio completion you cannot deliver.

Preflight remote capabilities, output format, account usability and the selected
publication destination before publication-dependent spending. Direct delivery
requires no publishing connection. Unavailable routes are blockers, not reasons
to switch creator, use a shared group, regenerate or run local Open Cloud.
Never claim Studio edits, imports, instance paths, screenshots, playback or
playtesting without those tools and actual evidence. Generated, prepared,
published, imported and gameplay-verified are distinct states.

### Studio-capable Codex

With exposed local Studio tools, follow the complete WORKFLOW, including the
selected place, studio_id, Edit-mode preflight, installation and verification.
Replace its Claude-specific connection diagnosis with the secure connection
guidance above. Use the host's question tool when available. Local helpers
require actual filesystem and execution access; their presence is not proof
that they can run. Stop and hand off any unsupported step.

## Safety gates in every runtime

Before remote work, read [publishing connections](references/publishing-connections.md),
[preparation and installation](references/preparation-installation.md), and
[project memory](references/project-manifest.md). Preserve the shared scope,
tenant, ownership, reference, publisher selection and pinned receipt rules.
Use only the authenticated account's owned jobs/assets and granted scopes;
never broaden scopes or supply another tenant/account ID to bypass a failure.
Free discovery uses library:read; owned status needs generation:read; paid
generation needs generation:write, account entitlement, explicit paid-work
authorization and a numeric ceiling covering the whole pipeline. Existing
authorization remains valid within its scope and ceiling; ask before exceeding
it. Credit cost remains unknown without billing evidence.

Reuse approved references before spending. Only pass owned image references in
fields supported by the live schema; a pasted image or URL is not a registered
reference. Retain style/version pins and distinguish job, asset, artifact and
publication identifiers. Resolve the user's intended publisher before paid
publication-dependent work; verify connection status, type, route and scopes.
Never choose the first connection or fall back to another creator. Keys belong
only in authenticated settings. Legacy publication is replay-only under the
shared contract, not a route for new requests.

Before submission, retain request_id and exact inputs in the ledger, then save
returned job_id/publication_id immediately. Poll the original status UUID.
For outcome_unknown or lost responses, preserve tool, inputs, request_id,
timestamp and correlation evidence. Never automatically resend, generate a new
request_id, republish or switch routes. Status schemas do not accept request_id;
without a status UUID, block pending operator reconciliation or an explicitly
supported read-only lookup. Keep pinned publication receipts, prepared member,
creator, moderation and access facts intact. Pending integrated delivery is
polled, not duplicated with standalone publication. A ready receipt must match
the intended creator; it does not prove Studio usability.

## Ledger and completion

Use forgegui-project.json and ledger v2 when filesystem access exists. Without
filesystem access, maintain the same decisions, paid ceiling/usage, reference
pins, exact requests, timestamps, job/artifact/prepared-member/publication IDs,
selected publisher and receipts in the response or a downloadable artifact.
Do not pretend to read or write a file. Carry this ledger into later turns;
if it is missing, reconcile before repeating work. Never include secrets.

Remote completion reports delivery state and explicit pending Studio handoff:
artifact links, prepared metadata, pinned receipts, unresolved moderation/access,
unknown outcomes and manual installation/verification steps. Leave Studio
verification unverified and do not set server Studio-verification flags.

All correctness-critical checks run from skill guidance in the current turn.
There is no Stop hook. An opted-in fidelity pass applies only with Studio and
reference access: run the shared fidelity guidance directly after verification,
within the paid ceiling. Store its state in the ledger if files are unavailable;
otherwise report it pending for the Studio handoff. Never wait for a hook.
