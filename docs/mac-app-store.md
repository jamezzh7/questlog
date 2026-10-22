# Building the Mac App Store target

The store target is a separate sandboxed build of Questlog. It embeds CPython and uses an in-process API bridge instead of the source launcher's external interpreter and local HTTP service. An Xcode archive is not an App Review approval or a published store release.

## Requirements

- Xcode with the macOS SDK and an Apple Developer team for signed builds.
- A Python.org CPython 3.13 framework with both desired architectures. Set `PYTHON_FRAMEWORK` in `store/Store.xcconfig` if it is installed elsewhere. Never redistribute a runtime from Xcode or Command Line Tools.
- No Python packages, web build tools or runtime downloads are required.

Copy `store/Local.xcconfig.example` to `store/Local.xcconfig`, enter your own team, and open `Questlog.xcodeproj`. The local file is ignored by Git. Select the Questlog scheme and build. Xcode signs embedded code with the same identity as the app; hardened runtime library validation therefore stays enabled.

For isolated testing, override the identifier and display name rather than replacing an installed copy:

```sh
xcodebuild -project Questlog.xcodeproj -scheme Questlog -configuration Debug \
  -derivedDataPath build-store \
  PRODUCT_BUNDLE_IDENTIFIER=com.example.questlog.qa \
  'QUESTLOG_DISPLAY_NAME=Questlog QA' build
```

The signed executable accepts `--store-smoke`. It reads the bundled fictional sample through the embedded runtime, checks a denied project request, restores the prior test configuration and exits. Use a distinct QA identifier. The `STORE_SCREENSHOTS` compilation condition sets the detail window to 1280 × 800 points for actual Retina captures; it is absent from normal release builds.

## Archive and export

```sh
xcodebuild -project Questlog.xcodeproj -scheme Questlog -configuration Release \
  -derivedDataPath build-store -archivePath artifacts/Questlog.xcarchive archive
```

Export using Xcode Organizer's App Store Connect workflow. An export requires a Mac App Store provisioning profile, application distribution identity and Mac Installer Distribution identity. Keep profiles, certificates, archives and export options out of Git. Let the account holder handle agreements and authentication. Never embed private keys or account credentials in scripts.

## Runtime and access boundaries

The runtime excludes site-packages, development tools, GUI modules, curses extensions, tests and bytecode caches. The build relocates bundled library paths, signs nested native code and retains the installed runtime's license notices. Python initialization ignores environment search paths and does not run site customization. The app does not execute downloaded Python code or Git hooks.

Folder and optional registry grants are read-only, persisted as security-scoped bookmarks, and passed from the native access manager to the shared API. The web view cannot supply those grants. An index grant never authorizes a listed project. Settings can revoke all saved grants; reauthorization leaves connection settings intact. No project file is written by Questlog.

WebKit requires the outgoing-network entitlement even to launch its local renderer on the verified macOS version. The app's local content has a restrictive CSP, an HTTP(S) blocking rule and a file-only navigation delegate. There is no listener, remote API, model integration or telemetry. The online policy opens separately in the user's browser.

Git context reads at most five first-parent commits directly from loose or v2-indexed packed objects, with size/read/delta-depth bounds. It does not follow Git metadata outside the selected project, including a worktree's external Git directory. Unsupported or unreadable metadata is optional and leaves main progress available.

## Submission material

`store/metadata.json` contains proposed English, Simplified Chinese and French copy. Check field limits and available names in App Store Connect. Publish and verify the [support](support.md) and [privacy](privacy.md) URLs before submission. Screenshots must show fictional data from the actual build and use an [Apple-supported Mac size](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

The privacy manifest declares local file metadata and elapsed time used for refresh/animation. No data collection is declared. Account contact information, distribution regions, trader declarations and encryption questionnaire answers belong to the owner-controlled submission workflow, not public source files.
