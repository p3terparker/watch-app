#!/usr/bin/env python3
"""Live YouTube stream resolution exactly as the player does it: the bundled yt-dlp through MediaTools' launch
boundary (same arguments and environment), with resolveStream's own format choice read from Sources/main.swift.
Reports, per public video, whether Watch would get a native stream or fall back, and yt-dlp's own error otherwise.
Informational: YouTube can bot-check data-centre addresses, so a failure here is a clue, not proof.
Run: python3 Tests/youtube_live.py <Watch.app/Contents/Helpers>"""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
VIDEOS = ['jNQXAC9IVRw', 'dQw4w9WgXcQ', 'kJQP7kiw5Fk']   # oldest upload · an official music video · a VEVO video
source = (ROOT / 'Sources/main.swift').read_text()
FORMAT = re.search(r'\? "(bv\*\[vcodec\^=avc1\]\[height<=1080\][^"]+)"', source).group(1)
helpers = Path(sys.argv[1]).resolve()
failures = 0
with tempfile.TemporaryDirectory(prefix='Watch youtube live ') as temp:
    home = Path(temp)
    shutil.copy2(ROOT / 'Tests/MediaToolsMain.swift', home / 'main.swift')
    subprocess.run(['xcrun', 'swiftc', str(ROOT / 'Sources/MediaTools.swift'), str(home / 'main.swift'), '-o', str(home / 'boundary')], check=True)
    env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(home), 'TMPDIR': str(home)}
    for video in VIDEOS:
        url = 'https://www.youtube.com/watch?v=' + video
        start = time.time()
        try:
            result = subprocess.run([str(home / 'boundary'), str(helpers), '-j', '--no-playlist', '--no-warnings', '-f', FORMAT, url],
                                    env=env, cwd=home, capture_output=True, text=True, timeout=120)
            code, out, err = result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            code, out, err = 'timeout', '', ''
        took = time.time() - start
        line = (out.splitlines() or [''])[0]
        try:
            info = json.loads(line)
        except ValueError:
            info = None
        if code == 0 and info:
            chosen = info.get('requested_formats') or [info]
            parts = ', '.join('{} {}/{} {}p {}'.format(f.get('format_id'), f.get('vcodec'), f.get('acodec'), f.get('height'), f.get('protocol')) for f in chosen)
            native = len(chosen) == 2 or any('m3u8' in str(f.get('protocol')) or f.get('ext') == 'mp4' for f in chosen)
            within = 'within' if took < 25 else 'OVER'
            print(f'OK   {video} in {took:.1f}s ({within} the player\'s 25 s wait) — {parts} — native: {native}', flush=True)
            if not native or took >= 25:
                failures += 1
        else:
            failures += 1
            errors = [l for l in err.splitlines() if 'ERROR' in l] or err.splitlines()[-8:]
            print(f'FAIL {video} after {took:.1f}s (exit {code}):', flush=True)
            for l in errors[-8:]:
                print('     ' + l, flush=True)
print(f'YouTube live resolution: {len(VIDEOS) - failures} of {len(VIDEOS)} would play natively in Watch', flush=True)
sys.exit(1 if failures else 0)
