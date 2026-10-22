# Mac App Store design

## Runtime

Keep the tested Python standard-library adapters. Embed a relocatable CPython framework in `Contents/Frameworks` and call a small JSON dispatcher through an Objective-C/Swift bridge. Initialize Python in isolated mode, set explicit bundled search paths, disable bytecode writes, and serialize calls. No shell commands, interpreter processes, listening sockets or downloaded runtime code are needed by the store app.

The existing `build_app.py` path remains usable. The Xcode target compiles a store-specific Swift runtime behind `APP_STORE`, loads bundled web resources, and uses `WKScriptMessageHandlerWithReply` for the JSON API. Navigation and frame origins are restricted to bundled content. The existing HTTP adapter remains a development/source distribution option, sharing validation and mutations with the native API.

## Permissions

A native access manager owns security-scoped folder and registry bookmarks. Persist grants in the app container and keep access active while needed. Pass only resolved authorized paths to the dispatcher. Python validates project access against that explicit list before reading, independently of the UI.

Manual connection uses a system folder picker. Tool discovery is opt-in: choose the specific Codex/Claude registry JSON, parse directory metadata without scanning unapproved projects, then request the chosen project's folder grant. Cancel leaves settings unchanged. Revoked or stale grants have a reauthorization path.

The entitlement set is App Sandbox, user-selected read-only files and app-scoped bookmarks. WebKit also requires the outgoing network capability to launch its renderer, including for bundled files; this was confirmed by the actual sandboxed launch log. Bundled content has a restrictive CSP, an HTTP(S) content-blocking rule and a local-file navigation delegate. The app has no network API or listener. No broad home-directory exception, full disk access, server, automation or administrator entitlement is used.

## Storage and compatibility

Resolve Application Support through Foundation inside the sandbox. Seed an empty configuration in the container. Existing settings outside the container are not silently imported; any future migration requires an explicit user selection. Store bookmarks separately from the adapter's human-readable project settings.

Git activity must be best-effort and must not require an external executable in the store app. Keep its unavailability distinct from main progress. Python resources and third-party notices must include applicable runtime licenses.

## Build and release

Use a dedicated Xcode project and shared scheme. Copy only standard-library runtime resources from an explicitly selected CPython installation during build; exclude site-packages, development files and bytecode caches. Relocate non-system library references, sign nested Mach-O files inside out and verify that no runtime dependency points outside the bundle or system libraries.

Do not commit signing identities, Team IDs, provisioning profiles, archives or local configuration. Configure the owner's team through an ignored local xcconfig or command-line override. Validate an isolated development build before creating a distribution archive. Keep submission notes and metadata separate from the running product.

## Verification

Run the existing Python and language suites plus API authorization/validation regressions. Exercise the embedded runtime with a fictional fixture and restricted environment. Verify the actual sandboxed app's picker cancellation, granted folder, relaunch persistence, denied paths, linked-file refresh, all three languages, details lifecycle and absence of child services. Check signing, bundle dependencies and Xcode archive output. Account-dependent upload follows only after these checks.
