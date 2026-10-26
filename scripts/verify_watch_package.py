#!/usr/bin/env python3
"""Verify the final read-only Watch DMG and preserve a versioned deliverable."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import watch_helpers

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--canonical', action='store_true', help='Verify Watch.dmg in place without making a versioned copy')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parent.parent
info = plistlib.loads((ROOT / 'Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
source = ROOT / 'dist/Watch.dmg'
versioned = source if args.canonical else ROOT / f'dist/Watch-{version}.dmg'
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def run(args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True).stdout.strip()
if not args.canonical:
    if versioned.exists() and sha(source) != sha(versioned):
        raise RuntimeError('Different versioned installer already exists; preserve it')
    shutil.copy2(source, versioned)
run(['hdiutil', 'verify', versioned])
with tempfile.TemporaryDirectory(prefix='watch-package-verify-') as temporary:
    mount = Path(temporary) / 'mounted'; mount.mkdir()
    run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, versioned])
    try:
        app = mount / 'Watch.app'
        executable = app / 'Contents/MacOS/Watch'
        metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        for key in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'LSMinimumSystemVersion'):
            assert metadata[key] == info[key], key
        archs = run(['lipo', '-archs', executable]).split()
        assert set(archs) == {'arm64', 'x86_64'}
        run(['codesign', '--verify', '--deep', '--strict', app])
        watch_helpers.validate_helpers(app)
        assert sha(executable) == sha(ROOT / 'build/universal/Watch.app/Contents/MacOS/Watch')
        assert (mount / 'Applications').is_symlink()
        assert (mount / 'Applications').readlink() == Path('/Applications')
        readme = (mount / 'Read Me.txt').read_text()
        assert readme == (ROOT / 'FIRST_RUN.txt').read_text()
        for tool in watch_helpers.TOOLS:
            assert (app / 'Contents/Helpers' / tool).stat().st_mode & 0o111
        assessment = subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)], capture_output=True, text=True)
        report = dict(version=version, build=metadata['CFBundleVersion'], architectures=archs,
                      minimum_macos=metadata['LSMinimumSystemVersion'], dmg_bytes=versioned.stat().st_size,
                      sha256=sha(versioned), executable_sha256=sha(executable),
                      codesign_verified=True, dmg_verified=True,
                      media_tools=json.loads((app / 'Contents/Resources/MediaTools.json').read_text()),
                      gatekeeper_exit=assessment.returncode, gatekeeper_output=assessment.stderr.strip())
        versioned.with_name(versioned.stem + '-verification.json').write_text(json.dumps(report, indent=2) + '\n')
        versioned.with_suffix('.dmg.sha256').write_text(report['sha256'] + '  ' + versioned.name + '\n')
        print(json.dumps(report, indent=2))
    finally:
        run(['hdiutil', 'detach', mount])
