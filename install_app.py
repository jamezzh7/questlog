#!/usr/bin/env python3
"""Install the built local app and keep user settings outside the source tree."""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IDENTIFIER = "local.questlog.companion"
REGISTER = Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")


def install(destination):
    source = ROOT / "Questlog.app"
    if not source.is_dir():
        raise ValueError("请先运行 python3 build_app.py")
    destination = destination.expanduser().absolute()
    if destination == source or destination.suffix != ".app":
        raise ValueError("安装位置必须是另一个 .app 路径")
    if destination.exists():
        info = plistlib.loads((destination / "Contents/Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != IDENTIFIER:
            raise ValueError("安装位置已有其他应用，未覆盖")
    runtime = json.loads((source / "Contents/Resources/runtime.json").read_text())
    if not os.access(runtime["python"], os.X_OK):
        raise ValueError("构建时的 Python 已不可用，请重新构建")
    support = Path.home() / "Library/Application Support/Questlog"
    settings = support / "projects.json"
    initial = Path(runtime["config"])
    if not initial.is_file():
        initial = ROOT / "projects.example.json"
    seed = initial.read_bytes()
    if not isinstance(json.loads(seed).get("projects"), list):
        raise ValueError("项目配置格式不正确，未安装")

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".questlog-install-", dir=destination.parent) as temporary:
        staging = Path(temporary) / "Questlog.app"
        shutil.copytree(source, staging, symlinks=True)
        runtime["config"] = str(settings)
        (staging / "Contents/Resources/runtime.json").write_text(json.dumps(runtime), encoding="utf-8")
        subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(staging)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(staging)], check=True)
        support.mkdir(parents=True, exist_ok=True, mode=0o700)
        if not settings.exists():
            with settings.open("xb") as stream:
                stream.write(seed)
            settings.chmod(0o600)
        backup = Path(temporary) / "previous.app"
        if destination.exists():
            destination.rename(backup)
        try:
            staging.rename(destination)
        except OSError:
            if backup.exists():
                backup.rename(destination)
            raise
    if REGISTER.is_file():
        subprocess.run([str(REGISTER), "-f", str(destination)], check=True)
    print(f"Installed: {destination}")
    print(f"Settings: {settings}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path("/Applications/Questlog.app"))
    install(parser.parse_args().destination)
