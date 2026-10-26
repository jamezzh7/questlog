# Architecture

Questlog has a native shell, a read-only Markdown adapter, and an on-demand local detail view.

| Component | Responsibility |
| --- | --- |
| `Questlog.swift` | AppKit widget, menus, window lifecycle, file metadata checks, WebKit details, native localization |
| `remote_snapshot.py` | Selected-project allowlist, no network; text opt-in and no local path/source metadata fields |
| `sync/` | Validated snapshot models, private CloudKit transport, independent Mac publisher and native sync settings |
| `phone/` | Read-only SwiftUI iPhone client, account-bound offline cache and foreground refresh |
| `read_summary.py` | One-shot widget summary, excluding Git; bounded document state when no plan exists |
| `progress.py` | Main checklist parsing, scope, groups, progress, and explicit hour estimates |
| `work_structure.py` | Bounded linked-plan parsing, module tasks, source states, and watched files |
| `discovery.py` | Optional local tool project discovery and candidate task-file selection |
| `project_status.py` | Evidence modes, bounded task aggregation, scope and app-owned goals |
| `project_context.py` | Bounded document excerpts and read-only source previews |
| `api_service.py` | Shared API validation, confined project access, and atomic settings writes |
| `server.py` | Source build's loopback HTTP transport and static detail assets |
| `store_api.py`, `store/` | Sandboxed in-process transport, embedded Python bridge and native file grants |
| `git_metadata.py` | Optional bounded Git commit reads without an executable in the store build |
| `public/` | Plain HTML/CSS/JavaScript details and translation catalog |
| `build_app.py`, `install_app.py` | Local bundle build, ad hoc signing, and settings-preserving installation |

## Widget lifecycle

The 300 × 120 pt window checks metadata every five seconds. Changed sources or manual refresh trigger a one-shot Python summary. Automatic sources are reconsidered about every 30 seconds. Without a task structure, a summary reads bounded status documents and watches their metadata. The idle widget does not keep a Python HTTP server or WebKit view alive.

The store build runs summaries in an isolated embedded Python interpreter on a serial queue. It does not launch an external interpreter. File access requires native read-only grants. The store configuration lives in its own sandbox container.

## Detail lifecycle

Opening details creates WKWebView and starts the bundled Python server on a random loopback port. The detail page polls while open. Collapsing details terminates the service and releases the web view. A parent-process watchdog also exits the server if its launcher disappears.

The store target instead loads bundled files and forwards API calls through a main-frame-restricted `WKScriptMessageHandlerWithReply`. The native layer supplies active folder/index grants, independently checked by the shared API. Remote content is blocked. Collapsing releases the web view; no listener or interpreter process is created. See the [store build guide](mac-app-store.md).

## Data model

A defined checklist scope, explicit main IDs or app-owned goals define the displayed percentage. Automatically detected partial plans show task counts without a percentage. Explicit document fields provide project state when no task structure exists. See [project state and scope](project-status.md). Linked module tasks retain explicit states and source attribution without inferred module percentages. Milestones, document sections, document excerpts, and Git activity provide context without silently changing the denominator.

The app writes only its own configuration. Path confinement, bounded reads, inert text rendering, and same-origin JSON writes are implementation boundaries, rather than UI-only conventions.

## Optional iCloud companion

Unprovisioned local builds do not contact CloudKit. Provisioned Cloud configurations automatically publish connected project summaries (except explicit exclusions, up to 50) once per minute independently of the detail view; the iPhone reads the private database using the same iCloud account and environment. Random remote IDs have no path meaning. One bounded JSON record per Mac is replaced atomically; paginated full queries replace the phone’s previous result and remove deleted snapshots. Observed active/blocker booleans are separate from prose. The iPhone uses one shared project-count and capture-freshness model for its adopted cards and details; cached copies are neutral. Optional activity metadata keeps version-1 payloads compatible with older clients. Status text has its own consent switch. Account changes disable publishing and clear phone state/navigation/cache. See [iCloud setup, schema and retention](icloud-sync.md).
