# History upload eligibility

The account review found a second failure path: an Apple Account change could fail to replace `sync-account.json` while the already open history database still accepted local visits. After quitting and returning to the previous account, both durable consent and cloud metadata could still name that account. A timestamp cutoff could then admit visits recorded while the account was unknown or unapproved.

The fix keeps local history and persists upload eligibility with each visit in SQLite schema 4:

- `HistoryStore.record` defaults to no upload epoch. A local visit receives an immutable epoch only when the main iCloud account choice and history metadata are verified and acknowledged. The history sharing toggle may still be off; sharing starts only after the user enables it.
- Startup before account verification, sign-out, main sync being off, and failed account or metadata persistence produce local-only visits. A later Retry or approval cannot promote those rows. Remote merges and duplicate IDs cannot add an epoch to an existing row.
- All three outgoing paths use `visitsForSync` or `daysForSync` with the current nonoptional epoch. Local lists, search and exported history remain available independently.
- Upload title and summary snapshots belong to the individual eligible visit. They never fall back to the latest shared page metadata. Updates require the originating visit ID and captured account scope. Native asynchronous description reads retain that complete scope from work start through completion.
- Each epoch writes separate cloud day records under `deviceID-epochUUID`. Payload visits still use the original device ID. The app recognizes its base ID and all its epoch writers when ingesting, avoiding re-importing its own records.
- Same-account epoch rotation preserves known record ownership for retention and history opt-out. Ordinary orphan cleanup rebuilds only the current writer. Explicit space deletion captures the original cloud space ID and account scope, then deletes known own records for that exact space across writers after the local deletion commits. Changed or unapproved account scope stays local.

Existing untagged history remains visible on this device and is not retroactively uploaded. Schema migration does not assign it to whichever Apple Account is seen next. Older cloud day records are not overwritten by the newly eligible subset. Retention uses its own cutoff, not the new upload-admission cutoff.

`HistoryUploadEligibilityTests` passes 8 tests in `/private/tmp/safience-visit-eligibility-tests.log`:

| Check | Exercised behavior |
| --- | --- |
| Consent write denial and stale A relaunch | Real directory permission denial prevents atomic consent replacement while SQLite WAL commits. Old matching A consent and metadata are loaded again. Startup, signed-out and B visits with future timestamps stay local; only tagged A visits are exportable to sync. |
| Queued history write | A real SQLite insert trigger fails, then Retry uses the original captured nil epoch after A approval. The visit remains local. |
| Metadata isolation | Same-URL B metadata, including a delayed B-origin callback under current A admission, cannot fill or replace A's empty or existing upload snapshots. Local page metadata remains available. |
| Merge and duplicate IDs | Remote merges and repeated local IDs cannot promote local-only rows or replace upload snapshots. |
| Legacy migration | A database with existing schema 3 visit/page rows is migrated and reopened. Local entries remain; upload queries and upload-day enumeration exclude them. |
| Writer namespace | Base, old-epoch and new-epoch day record names remain distinct and round-trip through the unchanged record parser. |
| Retention after epoch rotation | A new upload boundary does not expire retained old-writer days. Expired days still qualify for deletion. |
| Orphan versus explicit deletion | Ordinary cleanup affects only the current writer. Explicit removal includes base and old own writers for the exact space, excluding other spaces and devices. |

These are synthetic filesystem and SQLite tests using the production policy and store. They do not exercise real Apple Account switching or modify a production CloudKit database. Native description origin fixtures and final platform build results are recorded separately in the remediation validation document.
