# Mac App Store requirements

Status: implementation authorized by the owner; first release is free. Store submission remains subject to a tested archive and owner-controlled account access.

1. **Self-contained execution.** When launched on a supported Mac without Python, Git or Command Line Tools installed, the store app shall open its widget and read an authorized Markdown plan using bundled code only.
2. **Explicit file access.** When connecting a project, the store app shall obtain a read-only folder grant through the system picker, retain a security-scoped bookmark, and restore access after relaunch. Denied, stale or cancelled grants shall not create a connection or broaden access.
3. **Optional tool discovery.** When selecting Codex or Claude Code, the app shall request access to the relevant project registry before reading it. A discovered project shall require a separate folder grant before its files are inspected. It shall never read chat transcripts.
4. **Preserved progress.** When reading the same fixture, the store and existing adapters shall retain the same main counts, module states, linked-source limits, estimates and source attribution. Search, filtering, language switching, removal and window dragging shall continue to work.
5. **Contained persistence.** The store app shall write only its own sandbox container. Installing or testing it shall not overwrite the existing daily-use app, configuration, observed projects or tool registries.
6. **On-demand details.** When details open, the app shall communicate with bundled logic in-process. It shall not open a listening socket or spawn an external interpreter; closing details shall release the web view. The idle widget shall retain metadata-driven refresh.
7. **Release readiness.** The project shall build and archive through Xcode, have explicit sandbox entitlements and an embedded, relocatable runtime, and support development and distribution signing without committing credentials or local team settings.
8. **Submission preparation.** Before upload, the release shall have validated product metadata, privacy and support URLs, screenshots, a reproducible sample, and owner-approved account details. This work shall not accept agreements, purchase services or publish an untested build automatically.

The first store release is free, with no in-app purchases or accounts. Existing source builds remain available. A store adaptation is not a guarantee of App Review approval.
