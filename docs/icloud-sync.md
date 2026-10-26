# View Mac progress on iPhone

The optional iCloud companion is under **Unreleased**. It adds a read-only iPhone app; it is not yet a published iPhone App Store download. Existing local Mac builds still work without iCloud, and make no CloudKit requests. Provisioned iCloud builds automatically sync connected project summaries.

## Use

1. Install a provisioned `QuestlogCloud` Mac build and `QuestlogPhone` on the iPhone. Both must use the same iCloud account, CloudKit container and environment.
2. Connect a local project in Questlog on the Mac. Its summary syncs automatically; no pairing, project selection or separate Mac-name setup is required. New connections are included automatically.
3. Open Questlog on iPhone. Pull to refresh or use Refresh. The app refreshes about once per minute while active; background updates are not promised.
4. Keep the Mac awake with Questlog running. The publisher works when the details window is closed or the widget hidden. Quitting Questlog, sleep, lost file access or network failure stops new usable readings.

Only a confirmed tracking scope has a percentage. Incomplete plans show detected task counts and unknown coverage; state-only projects show their mode and, if enabled separately, short current/blocker/next excerpts. A snapshot is not a live job execution measurement. Jobs must update their plan/status evidence for Questlog to observe changes.

Each Mac shows its **capture time**. The phone separately shows its **last successful fetch time**. Snapshots over three minutes old, or with suspicious future clock times, are marked old. Refreshing the phone does not make an old Mac snapshot fresh. Failed or revoked project reads replace previous counts with an unavailable/permission state.

## Data and deletion

The private CloudKit database receives a random Mac identifier, a Mac display label, random project identifiers, connected, non-excluded project names, scope names, tracking modes, counts, optional scoped percentages, a source-conflict flag and capture time. **Share status text** is a separate, initially off option, limited to four short fields per project. Review text for confidential content before enabling it; common path redaction cannot remove arbitrary secrets from prose.

Local configuration, source documents, file path fields, source filenames/line metadata, Git history, directory bookmarks, transcripts and estimates are not part of the upload. No account/password service, public CloudKit database or developer-operated relay is used. Local HTTP endpoints remain loopback-only; the phone never accesses them.

Use **Questlog → iCloud sync…** only to stop syncing, exclude projects, rename the Mac or opt into status text. Uncheck a project and save to exclude it. Up to 50 projects sync at once; if more are connected, existing slots remain stable and spare slots fill automatically. An explicit stop remains off after restarting or connecting another project. Upgrading preserves previous disabled settings and converts formerly unselected connections into exclusions, while future connections join automatically. Existing cloud IDs and account bindings are retained.

Changing connections or saved exclusions atomically replaces this Mac's record, removing unselected projects. Choose **Stop and remove** on the originating Mac to delete its cloud snapshot. Keep that Mac online until removal is confirmed; a failed removal persists locally and retries on future launches. Merely quitting/uninstalling the Mac app leaves its last snapshot in iCloud. If the original Mac/settings are lost, manage the app's iCloud data through Apple's storage controls. Removing a connection excludes it from the next successful snapshot but does not change its source files.

The phone keeps a bounded offline copy for the verified iCloud identity. An account change clears displayed data, navigation and the disk cache. When offline, a previously verified-account cache may remain visible with the last fetch time; a cold launch that cannot verify identity does not reveal another account's cached data. Settings can clear the local copy; a later successful refresh may cache a new copy. The phone has no task editing, job control or Mac configuration endpoints.

## Build and provision

Requirements: Xcode with iOS 17+ SDK and simulator/device support, active Apple Developer membership for CloudKit provisioning, iCloud sign-in on both devices, and the existing Mac runtime prerequisites.

- `Questlog`: original sandbox Mac target, no iCloud entitlement by default.
- `QuestlogCloud`: same Mac target with `CloudDebug` / `CloudRelease` configurations.
- `QuestlogPhone`: new read-only iPhone target (`com.jamezzh7.questlog.iphone`).

Open `Questlog.xcodeproj`. Set your team using **Signing & Capabilities** or an ignored `store/Local.xcconfig` containing `DEVELOPMENT_TEAM = YOUR_TEAM_ID`. Do not commit team/profile credentials. For a fork, use your own app identifiers and container consistently in `sync/CloudKitTransport.swift`, `sync/MacCloud.entitlements` and `phone/QuestlogPhone.entitlements`.

Enable CloudKit for both App IDs, associate **the same** `iCloud.com.jamezzh7.questlog` container and refresh provisioning profiles. Debug/CloudDebug use **Development**; Release/CloudRelease use **Production**. Do not mix environments between devices. The local ad hoc `build_app.py` launcher cannot acquire CloudKit privileges by editing JSON or adding an entitlement to an unsigned app.

```sh
# iPhone UI/build verification without cloud provisioning
xcodebuild -project Questlog.xcodeproj -scheme QuestlogPhone \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath artifacts/phone-build CODE_SIGNING_ALLOWED=NO build

# Provisioned local Mac development build; use your configured team
xcodebuild -project Questlog.xcodeproj -scheme QuestlogCloud \
  -configuration CloudDebug -destination 'platform=macOS' \
  -derivedDataPath artifacts/mac-cloud-build -allowProvisioningUpdates build

sh scripts/check_sync.sh
python3 -m unittest discover -s tests -v
```

Debug iPhone builds accept `--preview` for explicitly labeled fictional examples. Preview mode makes no CloudKit requests. Release builds do not include the preview data/launch handling.

Development schema: custom private zone `QuestlogSnapshots`, record type `QuestlogDeviceSnapshot`, field `payload` of type **Bytes**. One version-1 JSON record (at most 400 KB) per Mac; up to 50 projects per record. Paginated queries require a **QUERYABLE index on recordName** for QuestlogDeviceSnapshot. In CloudKit Console → Development → Indexes, create an index such as recordNameQueryable, type QUERYABLE, field recordName. No payload index is required; full-result replacement removes deleted snapshots. The phone accepts at most 100 Macs and 4 MB of combined payloads. In Development, the first successful upload creates the schema; it can also be prepared in CloudKit Console. Before distributing Production builds, deploy the tested schema through Apple's console and verify both clients in Production. Do not reset the environment or deploy untested changes to resolve a transient error.

## Troubleshooting and acceptance

No account/restricted: check iCloud sign-in and device restrictions. Build permission errors: verify team, container, profile and matching environment. Network/service errors use bounded backoff and respect CloudKit retry-after. A failed upload never advances the displayed success time. CloudKit 15 with an HTTP 500 even for listing private zones is a server/container access failure; retain the diagnostic request ID privately and check the console and Apple service status rather than altering progress data.

Test real cloud acceptance using fictional projects: Mac upload → iPhone fetch → change task state → phone update → unselect project → phone removal → stop/remove → no remaining Mac snapshot. Separately verify sleep/stale timestamps, offline cache, revoked folder access and iCloud account changes. Simulator/UI and injected transport checks do not establish successful cloud delivery; report those results separately.

Official references: [enable CloudKit](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app), [configure iCloud services](https://developer.apple.com/documentation/xcode/configuring-icloud-services), [private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase), [paginated record queries](https://developer.apple.com/documentation/cloudkit/ckdatabase/records(matching:inzonewith:desiredkeys:resultslimit:)).
