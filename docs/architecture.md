# Architecture

Questlog has a native shell, a read-only Markdown adapter, and an on-demand local detail view.

| Component | Responsibility |
| --- | --- |
| `Questlog.swift` | AppKit widget, menus, window lifecycle, file metadata checks, WebKit details, native localization |
| `read_summary.py` | One-shot widget summary, excluding Git and general document context |
| `progress.py` | Main checklist parsing, scope, groups, progress, and explicit hour estimates |
| `work_structure.py` | Bounded linked-plan parsing, module tasks, source states, and watched files |
| `discovery.py` | Optional local tool project discovery and candidate task-file selection |
| `project_context.py` | Bounded document excerpts and read-only source previews |
| `server.py` | Loopback HTTP API, static detail assets, and atomic settings writes |
| `public/` | Plain HTML/CSS/JavaScript details and translation catalog |
| `build_app.py`, `install_app.py` | Local bundle build, ad hoc signing, and settings-preserving installation |

## Widget lifecycle

The 300 × 120 pt window checks metadata every five seconds. Changed sources or manual refresh trigger a one-shot Python summary. Auto-detected projects without a plan are checked periodically for a new plan. The idle widget does not keep a Python HTTP server or WebKit view alive.

## Detail lifecycle

Opening details creates WKWebView and starts the bundled Python server on a random loopback port. The detail page polls while open. Collapsing details terminates the service and releases the web view. A parent-process watchdog also exits the server if its launcher disappears.

## Data model

Main acceptance items define the overall percentage. Linked module tasks retain explicit states and source attribution without inferred module percentages. Milestones, document sections, document excerpts, and Git activity provide context without silently changing the denominator.

The app writes only its own configuration. Path confinement, bounded reads, inert text rendering, and same-origin JSON writes are implementation boundaries, rather than UI-only conventions.
