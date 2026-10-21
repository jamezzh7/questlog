# Privacy and local data

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

The installed app stores connections, source selections, task scopes, estimates, daily availability, and language preference in `~/Library/Application Support/Questlog/projects.json`. The development app has a separate source-tree configuration. The WebKit view may retain local view preferences through web storage.

Removing a connection removes its Questlog tracking settings, without removing the project directory or changing its source files. Updating the app preserves an existing installed configuration.

## Local HTTP service

The detail server runs only while needed and binds to `127.0.0.1`. It validates allowed hosts and same-origin JSON writes. It is intended for the app's local view, not public hosting or use by untrusted local clients. Other software with access to your user account is outside this boundary.

## Sharing diagnostics

Project paths, source text, and commit metadata can appear in screenshots and reports. Use fictional examples when sharing an issue. The included [Orbit sample](../examples/orbit/tasks.md) is safe demonstration data.
