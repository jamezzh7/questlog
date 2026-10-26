# iCloud progress companion

The approved first version connects a running Mac to a read-only iPhone app through the user's private CloudKit database. No Questlog registration or password service is introduced.

1. When a provisioned Mac build connects a project, Questlog shall automatically include its summary in iCloud sync without a separate setup or selection step. An explicit stop shall persist across launches and new connections; a fresh install without connections and an unprovisioned build shall make no CloudKit requests.
2. When automatically syncing, the Mac shall publish connected projects except explicit exclusions (up to 50 at once), using opaque device/project identifiers, display names, tracking mode, counts and confirmed-scope percentages. Status text requires a separate opt-in. Paths, Markdown documents, Git metadata, bookmarks and local configuration shall not be uploaded.
3. While Questlog is running and the Mac is awake, the publisher shall refresh approximately once per minute independently of the details window. Unreadable or revoked projects shall replace previous progress with an unavailable state.
4. When connections or exclusions change or sync is disabled, the Mac shall replace or delete its own snapshot, retrying deletion after network failure. The UI shall distinguish pending removal from completed removal.
5. When the iCloud account changes, publishing shall stop until explicitly re-enabled. The phone shall discard the previous account's displayed and cached data.
6. When the phone opens or the user refreshes, it shall fetch all Macs' latest snapshots, show per-Mac timestamps, flag stale data, and retain verified-account cached results during network failure. Unknown task coverage shall never become a percentage.
7. The phone shall not modify tasks, estimates, files, jobs or Mac settings. This version has no guaranteed background phone refresh, live job telemetry or wake/sleep control.
8. Source builds without valid iCloud capabilities shall explain that sync requires a properly provisioned build, while all existing local features continue working.

Developer provisioning, schema deployment and installation are validated separately from local builds. App Store submissions and listing/review assets are outside this change.

Upgrade acceptance: retain existing device/project UUIDs, account binding, status-text choice, explicit disabled state and previously unselected connections as exclusions. New connections auto-join. Signing into iCloud for the first time retries automatically; repeated notifications for the same account continue syncing, while switching a previously bound account still pauses for review.
