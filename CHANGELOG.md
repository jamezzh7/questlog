# Changelog

## Unreleased

- Show scoped completion, detected task counts, explicit project state or an unknown state according to the available evidence; keep percentages out of incomplete plans across native and web views.
- Prefer current and explicitly linked task plans, exclude README setup checks and historical examples, and combine bounded sources without double-counting matching tasks.
- Add Tracking scope with a named checklist or app-owned lightweight goals, persistent completion marks, preserved drafts and separate work estimates.

- Add a persistent Appearance setting with Follow system, Light and Dark options for the native widget, menu bar overview and details, localized in English, Simplified Chinese and French.
- Refresh the app icon and README screenshots; keep the compact native layout and add adaptive dark surfaces throughout the app.
- Fill each sidebar project icon and the selected project’s heading icon clockwise according to its main checklist progress, with sidebar completion counts and percentages in tooltips and accessible labels.
- Refresh progress for all connected sidebar projects, including inactive ones; show a dashed circle while loading or when a checklist is missing or unavailable.

## 0.13.0

- Add a native menu bar popover with progress rings, checklist counts and percentages for all connected projects.
- Open a project’s details directly, connect a project, open settings, refresh, or show and hide the widget from the popover.
- Read overview data only while the popover is open; isolate unreadable projects and preserve keyboard focus when data has not changed.
- Add English, Simplified Chinese and French labels, accessible project rows and a `⌘1` shortcut. The widget close button now hides it; quit remains available in the menu bar and with `⌘Q`.

## 0.12.0 — Mac App Store preparation

- Add a sandboxed Xcode target with an embedded, isolated CPython runtime and an in-process details API.
- Request read-only project and optional tool-index grants through system pickers; retain bookmarks and allow permission reset and recovery.
- Share API validation with source builds, retain all three interface languages, and read optional Git context without launching Git in the store build.
- Add privacy/support documents, runtime notices, submission copy and a real-interface screenshot workflow. Store release remains pending App Review.

## 0.11.0

- Add French across the native widget, menus, detail interface, errors, and accessibility labels.
- Persist the language selection and support French system locales, number formatting, and dates.
- Generate the native error catalog from the shared interface catalog without adding a JavaScript runtime.

## 0.10.2

- Restore window dragging through transparent native hit regions integrated with toolbar and sidebar space.
- Keep buttons, text selection, scrolling, and dialogs outside draggable regions.
- Preserve the compact widget's background dragging and on-demand detail lifecycle.

## 0.10.0

- Adapt to functional modules and linked Markdown work plans alongside existing checklists, milestone increments and ordinary sections; no project-specific module codes or paths.
- Read state-bearing task headings, Task/Status tables and module checkbox lists, retaining source lines, stable identities, priorities and full task notes.
- Keep main acceptance counts independent from module delivery and task acceptance subchecks. Distinguish explicit activity, planned readiness, prerequisites, deferral and unspecified state; do not infer module percentages.
- Open module tasks by default, support all/individual modules and main-checklist navigation, and preserve query, scope and expanded notes across refresh and temporary linked-source loss.
- Watch linked task files in the lightweight native path, including missing paths for automatic recovery; display readable source warnings while retaining the main progress reading.
- Bound local link traversal, exclude examples/history, discover standalone module plans and retain legacy scope/estimate behavior. Add nineteen adapter regression tests and native end-to-end checks, including qualified partial-completion states.

## 0.9.0

- Recompose the native floating widget around a large overall percentage, a quiet project name, main checklist count and secondary milestone/estimate row in 300 × 120 pt.
- Use readable system typography, neutral opaque surfaces, a fine border and a custom 4 pt progress track. Keep the native window shadow and avoid decorative effects.
- Ease changed progress for 360 ms, clamp the fill, show initial/project values directly and honor reduced motion. Stop the animation timer at completion.
- Give pin, expand and quit buttons quiet hover/press and selected states, accessible names and explicit Tab/Shift-Tab navigation with Space/Enter activation.
- Show a compact missing-estimate state and actionable tooltip; distinguish no checklist and no project from zero progress.
- Preserve the v0.8 detail reader, Python calculations, project settings, drag, context menu and on-demand service lifecycle.

## 0.8.0

- Rebuild the details as a focused project reader with a quiet sidebar and full-width task list.
- Keep scope, search, and filtering visible while reading; place project documents and Git activity in a dedicated view.
- Preserve existing data APIs, separate task counts, local configuration, and native window lifecycle.

## 0.7.0

- Inspect each milestone's actual tasks, switch back to the main acceptance checklist, filter by completion and search within the selected view.
- Group ordinary project checklists by document section without adding those groups to the overall denominator; retain explicitly configured main scopes and separate implementation milestones.
- Show attributed project document excerpts and recent commits even before a checklist exists, with read-only full-document previews and preference for explicit current/latest dated status entries.
- Choose a different progress source from detected Markdown plans or a relative path; preserve each plan's scope, dependencies and estimates, including estimates created during automatic detection.
- Allow manual connections without a checklist, detect Chinese plan filenames, and recover from a moved/deleted plan through the source picker.
- Keep selected stages stable when preceding text changes, keep search/filter state during file updates, and clear it when switching projects or sources.
- Add source confinement, scope preservation, automatic-plan, document context and detailed stage coverage; keep document/Git scans out of the lightweight widget.

## 0.6.0

- Remove a project connection from its sidebar row, with a clear confirmation and cancel action in Chinese and English.
- Keep project files and tool registries untouched; remove only the connection and its tracking settings.
- Switch to a neighboring project when removing the current one, keep the current view when removing another, and show a reconnectable empty state after the last removal.
- Clear native widget values and project menus when no connections remain, and ignore stale native read failures after a selection change.
- Add removal, unavailable-directory, reconnect, preference preservation and empty-summary regression coverage.

## 0.5.2

- Package a multi-resolution macOS icon and declare it in the application metadata so Finder can display it before launch.
- Use the same icon resource in the running app and Dock.
- Keep the existing progress-bar identity, with a soft white tile and slate-blue fill; include reproducible vector rendering source and PNG previews.

## 0.5.1

- Add a local installer for `/Applications/Questlog.app`, with app registration and signed bundle verification.
- Migrate the first installation's project settings to `~/Library/Application Support/Questlog/projects.json`; preserve existing settings on later installs.
- Point the installed bundle at its own resources and the persistent settings folder so it does not depend on the desktop source tree.
- Prefer the installed app from the convenience launcher.

## 0.5.0

- Place Connect Project directly below the project list; long lists still scroll independently while short lists keep the action near their last item.
- Give the connection action a visible accent surface, animated plus, hover/focus response, press feedback and an active dialog state that resets on close.
- Improve type legibility, sidebar selection, segmented controls and dialog appearance using Apple's macOS design guidance.
- Add accessible dialog labeling, a conventional action ellipsis, and a usable minimum detail-window size.
- Document design decisions and primary Apple references in `docs/macos-ui.md`.

## 0.4.0

- Keep the header and project sidebar in a fixed application shell; scroll content and long project lists independently.
- Add finite progress/count transitions, window and dialog fades, project entrance motion and hover feedback, with reduced-motion support.
- Add saved System / English / Simplified Chinese preferences across details, native widget, menus, dialogs and status messages.
- Preserve project-authored tasks and notes in their original language.
- Add language preference API and native-summary coverage plus translation completeness and interpolation checks.

## 0.3.0

- Discover local Codex and Claude Code projects from project registry metadata.
- Connect a listed project in one click, automatically find its Markdown task plan, or switch to an existing connection without replacing settings.
- Keep projects without a plan connected in an explicit waiting state; detect a task plan when it appears.
- Keep manual connection available, mark removed directories, and exclude remote roots, dependency folders and external symlinks.
- Add discovery and connection tests; do not read conversation transcripts or change tool configuration.

## 0.2.0

- Replace the large game scene with a 300×104 native progress widget in mist white and slate blue.
- Default to normal window stacking on one desktop. Pinning is optional; windows do not join other apps' fullscreen spaces.
- Load the WebKit details view and local HTTP service only on demand; release them when returning to the widget.
- Refresh native data only when the task/config files change. Skip Git and handoff reads in the compact adapter.
- Keep project switching, task filters, milestone tracking and explicit work estimates.
- Exclude machine-specific configuration and generated application bundles from version control.
- Add 18 data/API tests and an optional GitHub Actions template.
