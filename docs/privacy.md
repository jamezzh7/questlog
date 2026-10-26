# Privacy and local data

Last updated: October 25, 2026. [简体中文](privacy.zh-CN.md) · [Français](privacy.fr.md)

Questlog has no registration/password service, analytics, advertising, model integration or developer-operated backend. Unreleased builds add optional iCloud sync to a read-only iPhone companion; it is off by default. This describes the app; README badge images are separately requested by your browser when viewing the repository.

## What Questlog reads

- Connected Markdown checklists and explicitly linked local task plans, confined to the project root.
- File metadata needed to detect changes.
- Without a task structure, up to four known project documents provide explicit status fields for the widget and menu bar.
- In the detail view, a bounded selection of README, handoff, status, requirements, and delivery documents, with source attribution, plus recent Git activity.
- When you choose Codex or Claude Code discovery, project-directory metadata from their local registries or dedicated indexes.

Document context is limited to known project documentation locations, at most four excerpts, 2 MB per document, and 1,600 characters per excerpt. Linked task plans have separate limits described in [configuration](configuration.md).

Discovery does not read conversation JSONL or chat messages, start models, or change tool configuration. Manual connection is available when discovery is unnecessary or a tool's metadata format has changed.

Questlog does not intentionally read credential stores, `.env` files, application databases, or external project services. Content placed directly inside a selected Markdown document is part of that document and may be displayed; avoid putting secrets in task plans.

## What Questlog writes

Connections, source selections, task scopes, estimates, daily availability, language and appearance preferences, tracking scopes and lightweight goals remain on your Mac. The source-distributed installed app uses `~/Library/Application Support/Questlog/projects.json`; the development launcher uses a source-tree configuration. The Mac App Store build uses its own sandbox container and a `QuestlogStore` Application Support directory, with file-access bookmarks stored separately. The WebKit view may retain local view preferences through web storage.

Removing a connection removes its Questlog tracking settings, without removing the project directory or changing its source files. Updating the app preserves an existing installed configuration.

## Store build permissions and retention

The store build reads project files only after you choose a project folder in the macOS system dialog. Optional Codex or Claude Code discovery requires a separate, explicitly selected registry JSON file. Selecting an index does not authorize the project folders listed in it. All grants are read-only and can persist across launches through security-scoped bookmarks.

Settings → Reset file permissions forgets all saved folder and registry grants and stops their active access. Connections and estimates remain, and reading a project again requires a new folder selection. Remove a connection to delete its associated tracking settings. Neither action modifies the original project or tool registry. Local settings and web preferences remain until you remove them. Local-only use creates no cloud copy. Optional iCloud data and its removal are described below.

The store build embeds its runtime and uses an in-process bridge. It does not run a local HTTP server. WebKit requires macOS's outgoing network capability to start its renderer; the bundled page blocks remote requests and navigation. Questlog does not upload project files, paths, usage events or identifiers to the developer, and includes no analytics, advertising or model SDK. The existing local-only store submission is separate from this Unreleased feature; any future cloud-enabled submission must review its privacy disclosures before release.

## Optional iCloud companion (Unreleased)

Only after you enable sync and select projects, the native Mac publisher sends allowlisted snapshots to **your private CloudKit database** operated by Apple. A snapshot contains random device/project IDs, a chosen Mac label, selected project and scope names, tracking modes, counts, a source-conflict flag, optional scoped percentages and a capture timestamp. No local path fields, source files, filenames/line metadata, Git history, access bookmarks, conversations or estimates are included. Status prose is a separate, initially off option, limited to four short fields per project; it can contain confidential content and needs your review. Common inline-path redaction does not guarantee removal of secrets from prose.

The publisher refreshes about once per minute while Questlog is running and the Mac is awake, independently of the detail window. The phone reads snapshots with the same iCloud account and environment, and keeps a bounded local cache after verifying the account identity. Account changes clear phone data and stop Mac publishing until re-enabled. The developer has no app server receiving these snapshots. Apple's iCloud terms and storage rules apply.

Save a changed selection to remove unselected projects from the next cloud snapshot. On the originating Mac, choose **iPhone sync → Stop and remove** to delete its record. Failed deletion is retained locally and retried; keep the Mac online until confirmed. Quitting or uninstalling does not remove the cloud record. If the Mac/settings are lost, use Apple's app-specific iCloud storage controls. On iPhone, Settings can clear the offline copy; subsequent successful refreshes may create a new cache. See [setup, limits and retention](icloud-sync.md).

## Local HTTP service in source builds

The detail server runs only while needed and binds to `127.0.0.1`. It validates allowed hosts and same-origin JSON writes. It is intended for the app's local view, not public hosting or use by untrusted local clients. Other software with access to your user account is outside this boundary.

## Sharing diagnostics

Project paths, source text, and commit metadata can appear in screenshots and reports. Use fictional examples when sharing an issue. The included [Orbit sample](../examples/orbit/tasks.md) is safe demonstration data.

Opening the online policy or support links launches your browser. GitHub handles those website visits under its own privacy policy. If you choose to submit a support issue, the information you include is sent to GitHub; public issues are visible to others. Do not include private project content or credentials. Apple may separately handle App Store transactions or optional system diagnostics under Apple's policies.

Questlog is maintained by jamezzh7. For privacy questions, use the [support information](support.md) or [private security reporting](https://github.com/jamezzh7/questlog/security/advisories/new). Policy updates are published here with an updated date.
