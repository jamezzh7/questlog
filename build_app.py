#!/usr/bin/env python3
"""Build the small macOS launcher; application source stays in this project."""
import json
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if not (ROOT / "projects.json").exists():
    shutil.copy2(ROOT / "projects.example.json", ROOT / "projects.json")
APP = ROOT / "Questlog.app"
CONTENTS = APP / "Contents"
RESOURCES = CONTENTS / "Resources"
BIN = CONTENTS / "MacOS"
RESOURCES.mkdir(parents=True, exist_ok=True)
BIN.mkdir(parents=True, exist_ok=True)
for name in ("server.py", "progress.py", "read_summary.py", "discovery.py", "project_context.py", "work_structure.py"):
    shutil.copy2(ROOT / name, RESOURCES / name)
shutil.copytree(ROOT / "public", RESOURCES / "public", dirs_exist_ok=True)
# Share the web error catalog with the lightweight native widget, without a JS runtime.
error_catalog = re.search(r"const errors = (\{.*?\});", (ROOT / "public/i18n.js").read_text(), re.S)
if not error_catalog:
    raise ValueError("Missing error translation catalog")
(RESOURCES / "errors.json").write_text(json.dumps(json.loads(error_catalog[1]), ensure_ascii=False), encoding="utf-8")
shutil.copy2(ROOT / "assets/AppIcon.icns", RESOURCES / "AppIcon.icns")
(RESOURCES / "runtime.json").write_text(json.dumps({"python": shutil.which("python3"), "config": str(ROOT / "projects.json")}), encoding="utf-8")
with (CONTENTS / "Info.plist").open("wb") as stream:
    plistlib.dump({"CFBundleName": "Questlog", "CFBundleDisplayName": "Questlog",
                  "CFBundleIdentifier": "local.questlog.companion", "CFBundleExecutable": "Questlog",
                  "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.11.0", "CFBundleVersion": "0.11.0",
                  "CFBundleIconFile": "AppIcon.icns",
                  "LSApplicationCategoryType": "public.app-category.productivity",
                  "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "zh-Hans", "fr"],
                  "NSHighResolutionCapable": True, "LSMinimumSystemVersion": "13.0",
                  "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}, stream)
subprocess.run(["swiftc", str(ROOT / "Questlog.swift"), "-o", str(BIN / "Questlog"),
                "-module-cache-path", "/tmp/questlog-swift-cache", "-framework", "AppKit", "-framework", "WebKit"], check=True)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(APP)], check=True)
print(APP)
