#!/usr/bin/env python3
"""Compile the real panel with an isolated entry point; no app lifecycle, cookies or playback.
Run: python3 Tests/panel.py [snapshot-directory]
Requires a macOS GUI session. All source substitutions occur in a temporary directory.
"""
import json
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
snapshots = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/watch-panel-checks'
snapshots.mkdir(parents=True, exist_ok=True)
config = json.loads((root / 'scripts/app.json').read_text())
app = config
with tempfile.TemporaryDirectory(prefix='watch-panel-') as scratch:
    scratch = pathlib.Path(scratch)
    sources = []
    for source in sorted((root / 'Sources').glob('*.swift')):
        text = source.read_text()
        if source.name == 'main.swift':
            text = text.split('// MARK: - Entry point')[0]
            text += (root / 'Tests/PanelMain.swift').read_text()
        domain = 'UserDefaults(suiteName: "glasskit-watch-panel-tests-\\(ProcessInfo.processInfo.processIdentifier)")!'
        text = text.replace('UserDefaults.standard', domain).replace('defaults: .standard', 'defaults: ' + domain)
        target = scratch / source.name
        target.write_text(text)
        sources.append(str(target))
    binary = scratch / 'WatchPanelTests'
    command = ['xcrun', 'swiftc', '-swift-version', config['swift_version'], *sources, '-o', str(binary)]
    for framework in app['frameworks']:
        command += ['-framework', framework]
    subprocess.run(command, check=True)
    subprocess.run([str(binary), str(snapshots.resolve())], check=True)
