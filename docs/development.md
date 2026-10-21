# Development

## Prerequisites

Use macOS 13+, Python 3.9+, and Apple Command Line Tools for native development. Node.js 22+ is recommended for JavaScript checks. Python and frontend code need no package installation.

```sh
python3 --version
swiftc --version
node --version
```

Install Command Line Tools with `xcode-select --install` if needed. If full Xcode is selected but unavailable and standalone tools are installed, use the installed Command Line Tools for this invocation:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools python3 build_app.py
```

This does not change the globally selected developer directory.

## Build and update

```sh
python3 build_app.py
# Quit the running Questlog before replacing it.
python3 install_app.py
open /Applications/Questlog.app
```

The build creates an empty `projects.json` from `projects.example.json` only when one does not exist. The development bundle reads this source-tree configuration. The installer uses `~/Library/Application Support/Questlog/projects.json`, copying initial settings on first installation and preserving existing settings on updates.

The native bundle records an absolute Python interpreter path. Build on the target Mac and rebuild if that interpreter moves. Locally built apps are ad hoc signed; this is not a Developer ID signature or Apple notarization. Building alone does not update an installed app.

## Browser preview

Create a separate configuration to keep preview changes isolated:

```sh
cp projects.example.json /tmp/questlog-preview.json
python3 server.py --config /tmp/questlog-preview.json --port 4318
```

Open `http://127.0.0.1:4318/?view=full` and connect a fictional sample project. Stop the preview with `Ctrl-C`. The native app starts its own detail service on an available random port; the fixed preview port is only for development.

## Checks

```sh
python3 -m unittest discover -s tests -v
node --test tests/test_i18n.cjs
node --check public/app.js
node --check public/i18n.js
python3 -m py_compile discovery.py progress.py project_context.py work_structure.py read_summary.py server.py build_app.py install_app.py
```

Native changes also require a Swift build and actual app verification. Check source selection, language changes, project switching, keyboard navigation, and collapse/quit lifecycle as relevant to the change. UI screenshots should use fictional data.

Keep generated test bundles out of normal application search results. After native QA, quit the test app, unregister its exact bundle path if registered, and remove the reproducible test bundle or archive it as ZIP. Keep the installed daily-use app intact.

## Assets

```sh
swift -module-cache-path /tmp/questlog-swift-cache scripts/render_app_icon.swift assets
swift -module-cache-path /tmp/questlog-swift-cache scripts/render_ui_symbols.swift public/icons.png
```

Commit regenerated assets with their drawing changes. Apple-provided symbols remain subject to Apple's terms; see [notices](../THIRD_PARTY_NOTICES.md).
