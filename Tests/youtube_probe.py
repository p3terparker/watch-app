#!/usr/bin/env python3
"""Diagnostic: the player's YouTube pipeline on real links (resolveStream → plans → DashHLSBridge → AVPlayer), with
the bundled helpers, reporting each step — formats, each file's sidx, playlist sizes, and whether playback starts and
keeps going at the start, middle and near the end. Informational; YouTube can bot-check data-centre addresses.
Run: python3 Tests/youtube_probe.py <Helpers directory> <link>...
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
helpers = pathlib.Path(sys.argv[1]).resolve()
links = sys.argv[2:]
app = json.loads((root / 'scripts/app.json').read_text())

with tempfile.TemporaryDirectory(prefix='watch-youtube-probe-') as scratch:
    scratch = pathlib.Path(scratch)
    sources = []
    for source in sorted((root / 'Sources').glob('*.swift')):
        text = source.read_text()
        if source.name == 'main.swift':
            text = text.split('// MARK: - Entry point')[0]
            # Let the probe read the bridge's index and playlists.
            for private in ('private var playlists', 'private static func fetchIndex', 'private static func boxes',
                            'private static func parse'):
                assert private in text, private
                text = text.replace(private, private.replace('private ', ''))
            text += (root / 'Tests/YouTubeProbeMain.swift').read_text()
        target = scratch / source.name
        target.write_text(text)
        sources.append(str(target))
    # MediaTools.bundled is <Bundle.main>/Contents/Helpers; a command-line tool's bundle is its own folder.
    (scratch / 'Contents').mkdir()
    (scratch / 'Contents/Helpers').symlink_to(helpers)
    binary = scratch / 'probe'
    command = ['xcrun', 'swiftc', '-swift-version', app['swift_version'], *sources, '-o', str(binary)]
    for framework in app['frameworks']:
        command += ['-framework', framework]
    subprocess.run(command, check=True)
    home = scratch / 'home'
    home.mkdir()
    env = dict(os.environ, HOME=str(home), TMPDIR=str(scratch))
    sys.exit(subprocess.run([str(binary), *links], env=env, cwd=scratch, timeout=1500).returncode)
