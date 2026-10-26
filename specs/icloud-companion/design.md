# Design

Mac's bounded local reader → allowlisted snapshot → CloudKit private custom zone → read-only SwiftUI iPhone app. Both applications use `iCloud.com.jamezzh7.questlog`. Separate CloudDebug/CloudRelease configurations opt into capabilities; the existing local build remains usable without them.

One `QuestlogDeviceSnapshot` record per random Mac identifier contains a versioned JSON payload, bounded to 50 projects and 400 KB. Replacing this record atomically removes unselected projects. Each project has a locally persisted random UUID unrelated to its path. A custom private zone and paginated full-snapshot queries use a queryable index on recordName. Only the owning Mac writes/deletes its record. No public database, web server, analytics or third-party SDK is used.

Provisioned builds default to automatic sync. The publisher reconciles connection IDs at launch, when the local configuration changes and on its independent timer; it does not scan source files to discover connections. Explicit exclusions are separate from the derived selection. Upgrades translate the old unselected connections into exclusions once, preserving existing IDs and disabled state. More than 50 eligible connections retain existing slots and fill spare slots deterministically; settings disclose the limit. No-project fresh installs and unprovisioned builds make no cloud calls.

Sync settings are stored separately beside the existing configuration, written atomically with private permissions. A single publisher serializes reads, uploads and deletion; preference generations prevent obsolete reads from being published, and pending updates follow any in-flight upload. CloudKit retry-after and bounded exponential backoff avoid request loops. A failed upload does not advance the last-success timestamp. Account notifications trigger identity verification; a repeated notification for the same account keeps publishing, while an actual different identity disables publishing and clears phone caches. A temporarily signed-out Mac retains its binding and does not publish; signing into that same account resumes automatically.

The phone checks the iCloud identity before loading its account-bound cache, fetches when active, refreshes about once per minute and supports pull-to-refresh. Each Mac's capture time is distinct from the phone's last successful fetch. Snapshots older than three minutes are marked stale; no claim that an offline Mac is still running is made. A missing zone means no shared projects. Malformed, oversized or unsupported records produce a visible failure rather than a falsely fresh result.

## Interface specification

Purpose: choose which Mac projects can be viewed on the phone, and make freshness and progress scope understandable at a glance.

Aesthetic direction: utilitarian, extending Questlog's approved flat visual system. Light paper `#FBFBFB`, ink `#242424`, accent `#4A61A8`; dark surface `#242424`, ink `#EDEDED`. Typography uses the existing macOS system font and native iOS San Francisco, overriding generic web-font guidance to preserve platform accessibility and Dynamic Type. SF Symbols supply icons. No decorative gradients or new branding.

Mac: connecting a project explains that summaries sync automatically to the same iCloud account. The optional iCloud sync window contains status, a default Mac label, an automatic-sync checkbox, independent status-text checkbox, project exclusions, save/refresh and stop/remove controls. No settings visit is required. The phone empty state asks only to connect a Mac project and use the same iCloud account. Phone: leading-aligned navigation list grouped by Mac; rows show names and scoped progress or task/status counts. Detail uses native sections for scope, counts, optional current/blocker/next text and timestamps. Standard native layout overrides creative asymmetric web-layout guidance because this is a compact companion utility.

## Verification

Python tests cover selection boundaries, allowlisted keys, opt-in text, read failures, permission revocation and progress modes. Swift tests cover strict payload validation, opaque IDs, stale states and preference persistence. Build the legacy Mac app, sandbox Mac configurations and iOS simulator/device targets. Exercise the real phone UI with explicitly labeled fictional preview data; preview mode cannot contact CloudKit. Real two-device CloudKit acceptance requires provisioned capabilities and the same iCloud account, and is reported separately.

Live validation found repeated timeouts on the zone-change endpoint while record lookup/query requests worked. The reader uses paginated snapshot queries instead; recordName QUERYABLE is part of setup and must be deployed with the schema.


## iPhone presentation completion

Version 1 gains an optional `activity` object with boolean `active` and `blocked`. New publishers derive it from bounded task counts and explicit document evidence before optional prose is removed. Unreadable records omit it. Existing clients ignore it; new clients accept old records/caches and fall back to counts and shared blocker signals. No CloudKit schema migration is required because the payload remains a Bytes field. No new file data or project text is transmitted.

`SnapshotOverview` counts projects for every metric. A project can have active work and a blocker simultaneously. `DeviceSnapshot.freshness` is shared by the header and detail: future clock skew, saved cache, stale and recent are distinct. The existing indicator becomes a static capture indicator; cached data is neutral. Card composition and navigation remain as adopted.

The phone Info.plist expands `CODE_SIGNING_ALLOWED` into its CloudKit intent flag. Unsigned builds fail closed before CKContainer construction; signed builds retain their existing capability configuration. This does not replace provisioning validation. See Apple's [build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference). Debug-only preview variants exercise hidden prose and cached presentation without touching iCloud.
