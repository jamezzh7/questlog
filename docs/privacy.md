# Privacy and local data

Last updated: October 22, 2026. [简体中文](privacy.zh-CN.md) · [Français](privacy.fr.md)

Questlog has no account system, analytics, model integration, or remote backend. This describes the app; README badge images are separately requested by your browser when viewing the repository.

## What Questlog reads

- Connected Markdown checklists and explicitly linked local task plans, confined to the project root.
- File metadata needed to detect changes.
- In the detail view, a bounded selection of README, handoff, status, requirements, and delivery documents, with source attribution, plus recent Git activity.
- When you choose Codex or Claude Code discovery, project-directory metadata from their local registries or dedicated indexes.

Document context is limited to known project documentation locations, at most four excerpts, 2 MB per document, and 1,600 characters per excerpt. Linked task plans have separate limits described in [configuration](configuration.md).

Discovery does not read conversation JSONL or chat messages, start models, or change tool configuration. Manual connection is available when discovery is unnecessary or a tool's metadata format has changed.

Questlog does not intentionally read credential stores, `.env` files, application databases, or external project services. Content placed directly inside a selected Markdown document is part of that document and may be displayed; avoid putting secrets in task plans.

## What Questlog writes

Connections, source selections, task scopes, estimates, daily availability, and language preference remain on your Mac. The source-distributed installed app uses `~/Library/Application Support/Questlog/projects.json`; the development launcher uses a source-tree configuration. The Mac App Store build uses its own sandbox container and a `QuestlogStore` Application Support directory, with file-access bookmarks stored separately. The WebKit view may retain local view preferences through web storage.

Removing a connection removes its Questlog tracking settings, without removing the project directory or changing its source files. Updating the app preserves an existing installed configuration.

## Store build permissions and retention

The store build reads project files only after you choose a project folder in the macOS system dialog. Optional Codex or Claude Code discovery requires a separate, explicitly selected registry JSON file. Selecting an index does not authorize the project folders listed in it. All grants are read-only and can persist across launches through security-scoped bookmarks.

Settings → Reset file permissions forgets all saved folder and registry grants and stops their active access. Connections and estimates remain, and reading a project again requires a new folder selection. Remove a connection to delete its associated tracking settings. Neither action modifies the original project or tool registry. Local settings and web preferences remain until you remove them; Questlog has no server copy, account or remote deletion process.

The store build embeds its runtime and uses an in-process bridge. It does not run a local HTTP server. WebKit requires macOS's outgoing network capability to start its renderer; the bundled page blocks remote requests and navigation. Questlog does not upload project files, paths, usage events or identifiers to the developer, and includes no analytics, advertising or model SDK. Its privacy declaration is “Data Not Collected.”

## Local HTTP service in source builds

The detail server runs only while needed and binds to `127.0.0.1`. It validates allowed hosts and same-origin JSON writes. It is intended for the app's local view, not public hosting or use by untrusted local clients. Other software with access to your user account is outside this boundary.

## Sharing diagnostics

Project paths, source text, and commit metadata can appear in screenshots and reports. Use fictional examples when sharing an issue. The included [Orbit sample](../examples/orbit/tasks.md) is safe demonstration data.

Opening the online policy or support links launches your browser. GitHub handles those website visits under its own privacy policy. If you choose to submit a support issue, the information you include is sent to GitHub; public issues are visible to others. Do not include private project content or credentials. Apple may separately handle App Store transactions or optional system diagnostics under Apple's policies.

Questlog is maintained by jamezzh7. For privacy questions, use the [support information](support.md) or [private security reporting](https://github.com/jamezzh7/questlog/security/advisories/new). Policy updates are published here with an updated date.
