#!/usr/bin/env python3
"""Embed an explicit CPython 3.13 framework; never download or install a runtime."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
MACHO = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}
MODULES = ('progress.py', 'work_structure.py', 'discovery.py', 'project_context.py', 'read_summary.py', 'api_service.py', 'store_api.py', 'git_metadata.py')


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def dependencies(path):
    return [line.strip().split(' (', 1)[0] for line in run('/usr/bin/otool', '-L', str(path)).splitlines()
            if line.startswith(('\t', '    '))]


def machos(directory):
    result = []
    for path in directory.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO: result.append(path)
    return result


def copy_runtime(source, destination):
    if source.name != '3.13' or not (source / 'Python').is_file():
        raise ValueError('Use an explicit CPython 3.13 framework version directory')
    if any(part in source.parts for part in ('Xcode.app', 'CommandLineTools')):
        raise ValueError('Apple development-tool runtimes must not be redistributed')
    fingerprint = hashlib.sha256((source / 'Python').read_bytes() + b'questlog-runtime-2-no-curses').hexdigest()
    stamp = destination / 'Versions/3.13/Resources/runtime.sha256'
    if stamp.is_file() and stamp.read_text() == fingerprint:
        return
    if destination.exists(): shutil.rmtree(destination)
    version = destination / 'Versions/3.13'
    version.mkdir(parents=True)
    shutil.copy2(source / 'Python', version / 'Python')
    ignored = shutil.ignore_patterns('site-packages', '__pycache__', '*.pyc', 'test', 'tests', 'idlelib', 'turtledemo', 'tkinter', 'ensurepip', 'venv', 'config-3.13-darwin', '_test*', '_tkinter*', '_curses*')
    shutil.copytree(source / 'lib/python3.13', version / 'lib/python3.13', ignore=ignored)
    resources = version / 'Resources'; resources.mkdir()
    metadata = plistlib.loads((source / 'Resources/Info.plist').read_bytes())
    metadata['CFBundleIdentifier'] = 'org.python.Python'
    (resources / 'Info.plist').write_bytes(plistlib.dumps(metadata))
    shutil.copy2(source / 'lib/python3.13/LICENSE.txt', resources / 'Python-LICENSE.txt')
    shutil.copy2(source / 'Resources/English.lproj/Documentation/_sources/license.rst.txt', resources / 'Python-History-and-Licenses.txt')
    # Native standard-library extensions may depend on bundled OpenSSL/curses.
    copied = set()
    while True:
        needed = {dep for binary in machos(version) for dep in dependencies(binary)
                  if dep.startswith(str(source) + '/lib/')}
        pending = needed - copied
        if not pending: break
        for dependency in pending:
            origin = Path(dependency)
            relative = origin.relative_to(source)
            target = version / relative; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(origin, target); copied.add(dependency)
    (destination / 'Versions/Current').symlink_to('3.13')
    (destination / 'Python').symlink_to('Versions/Current/Python')
    (destination / 'Resources').symlink_to('Versions/Current/Resources')
    stamp.write_text(fingerprint)


def prepare(app, framework, identity):
    app = app.resolve(); source = framework.resolve()
    resources = app / 'Contents/Resources'; resources.mkdir(parents=True, exist_ok=True)
    for name in MODULES:
        shutil.copy2(ROOT / name, resources / name)
    shutil.copy2(ROOT / 'store/PrivacyInfo.xcprivacy', resources / 'PrivacyInfo.xcprivacy')
    shutil.copytree(ROOT / 'public', resources / 'public', dirs_exist_ok=True)
    # File-origin mask images can be rejected by WebKit's CORS checks. Keep the
    # existing atlas local and inline its bytes in the store stylesheet.
    style = resources / 'public/style.css'
    atlas = base64.b64encode((ROOT / 'public/icons.png').read_bytes()).decode('ascii')
    style.write_text(style.read_text().replace("url('icons.png')", "url('data:image/png;base64," + atlas + "')"))
    index = resources / 'public/index.html'
    policy = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'none'; frame-src 'none'; object-src 'none'"
    index.write_text(index.read_text().replace('<head>', '<head>\n  <meta http-equiv="Content-Security-Policy" content="' + policy + '">', 1))
    shutil.copytree(ROOT / 'examples/orbit', resources / 'SampleProject', dirs_exist_ok=True)
    shutil.copy2(ROOT / 'assets/AppIcon.icns', resources / 'AppIcon.icns')
    shutil.copy2(ROOT / 'LICENSE', resources / 'Questlog-LICENSE.txt')
    shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', resources / 'THIRD_PARTY_NOTICES.md')
    errors = re.search(r'const errors = (\{.*?\});', (ROOT / 'public/i18n.js').read_text(), re.S)
    (resources / 'errors.json').write_text(json.dumps(json.loads(errors[1]), ensure_ascii=False))
    destination = app / 'Contents/Frameworks/Python.framework'
    copy_runtime(source, destination)
    shutil.copy2(ROOT / 'store/PrivacyInfo.xcprivacy', destination / 'Versions/3.13/Resources/PrivacyInfo.xcprivacy')
    libraries = machos(destination)
    binary = app / 'Contents/MacOS/Questlog'
    all_code = libraries + ([binary] if binary.exists() else [])
    source_framework = str(source.parent.parent)
    for item in all_code:
        for dependency in dict.fromkeys(dependencies(item)):
            if dependency.startswith(source_framework + '/'):
                replacement = '@rpath/Python.framework/' + dependency[len(source_framework)+1:]
                subprocess.run(['/usr/bin/install_name_tool', '-change', dependency, replacement, str(item)], check=True, stdout=subprocess.DEVNULL)
            elif dependency.startswith('/') and not dependency.startswith(('/usr/lib/', '/System/Library/')):
                raise ValueError('Unbundled native dependency: ' + dependency)
        if item == destination / 'Versions/3.13/Python':
            subprocess.run(['/usr/bin/install_name_tool', '-id', '@rpath/Python.framework/Versions/3.13/Python', str(item)], check=True)
        elif item.suffix == '.dylib':
            subprocess.run(['/usr/bin/install_name_tool', '-id', '@rpath/Python.framework/' + str(item.relative_to(destination)), str(item)], check=True)
    for item in sorted(libraries, key=lambda p: len(p.parts), reverse=True):
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', identity, str(item)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', identity, str(destination)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for item in all_code:
        for dependency in dependencies(item):
            if dependency.startswith('/') and not dependency.startswith(('/usr/lib/', '/System/Library/')):
                raise ValueError('Absolute runtime dependency remains: ' + dependency)
    print(json.dumps({'bundled_runtime':'CPython 3.13','native_components':len(libraries),'external_runtime_paths':False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--framework', required=True, type=Path)
    parser.add_argument('--identity', default='-')
    arguments = parser.parse_args()
    prepare(arguments.app, arguments.framework, arguments.identity or '-')
