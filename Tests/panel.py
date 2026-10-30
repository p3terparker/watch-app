#!/usr/bin/env python3
"""Compile the real panel with an isolated entry point; no app lifecycle, cookies or playback of anything online.
Run: python3 Tests/panel.py [snapshot-directory]
Requires a macOS GUI session. All source substitutions occur in a temporary directory.
With a built Watch.app (build/universal or build/native), its bundled FFmpeg also makes local test media so the real
player is exercised end to end: a video for the click zones / keys / resizing, and DASH-style renditions served over
a local byte-range HTTP server for the quality-switching bridge. Without one, those checks are skipped.
"""
import functools
import http.server
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import threading

root = pathlib.Path(__file__).resolve().parents[1]
snapshots = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/watch-panel-checks'
snapshots.mkdir(parents=True, exist_ok=True)
config = json.loads((root / 'scripts/app.json').read_text())
app = config


class RangeHandler(http.server.SimpleHTTPRequestHandler):
    """Static files with HTTP byte ranges, as YouTube's CDN serves them (DashHLSBridge reads indexes and segments by range)."""
    remaining = None

    def log_message(self, *args):
        pass

    def send_head(self):
        path = self.translate_path(self.path)
        header = self.headers.get('Range', '')
        if not os.path.isfile(path) or not header.startswith('bytes='):
            return super().send_head()
        size = os.path.getsize(path)
        first, _, last = header[6:].partition('-')
        start = int(first) if first else 0
        end = min(int(last) if last else size - 1, size - 1)
        source = open(path, 'rb')
        source.seek(start)
        self.send_response(206)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.send_header('Content-Length', str(end - start + 1))
        self.end_headers()
        self.remaining = end - start + 1
        return source

    def copyfile(self, source, outputfile):
        if self.remaining is None:
            return super().copyfile(source, outputfile)
        while self.remaining > 0:
            chunk = source.read(min(65536, self.remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            self.remaining -= len(chunk)
        self.remaining = None


def media_fixtures(folder):
    """Test media made by the built app's own FFmpeg; {} when there's no build to take it from."""
    ffmpeg = next((p for p in (root / 'build/universal/Watch.app/Contents/Helpers/ffmpeg',
                               root / 'build/native/Watch.app/Contents/Helpers/ffmpeg') if p.is_file()), None)
    if ffmpeg is None:
        print('SKIP player and bridge checks: no built Watch.app with FFmpeg', flush=True)
        return {}
    # YouTube's layout: ftyp, moov, one sidx indexing every fragment, then moof/mdat pairs (2 s each here; audio has no
    # keyframes to split on, so it's split by duration).
    fragmented = ['-movflags', '+frag_keyframe+empty_moov+default_base_moof+global_sidx']
    jobs = {
        'player.mp4': ['-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100',
                       '-t', '40', '-c:v', 'h264_videotoolbox', '-b:v', '800k', '-g', '24', '-c:a', 'aac', '-movflags', '+faststart'],
        'v360.mp4': ['-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-t', '60', '-c:v', 'h264_videotoolbox', '-b:v', '500k',
                     '-g', '48', '-an'] + fragmented,
        'v180.mp4': ['-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=24', '-t', '60', '-c:v', 'h264_videotoolbox', '-b:v', '200k',
                     '-g', '48', '-an'] + fragmented,
        'a.m4a': ['-f', 'lavfi', '-i', 'sine=frequency=330:sample_rate=44100', '-t', '60', '-c:a', 'aac', '-b:a', '128k', '-vn',
                  '-frag_duration', '2000000', '-movflags', '+empty_moov+default_base_moof+global_sidx'],
    }
    for name, args in jobs.items():
        result = subprocess.run([str(ffmpeg), '-v', 'error', '-y', *args, str(folder / name)], capture_output=True, text=True)
        if result.returncode != 0:
            print(f'SKIP player and bridge checks: FFmpeg could not make {name}: {result.stderr[-400:]}', flush=True)
            return {}
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(RangeHandler, directory=str(folder)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return {'WATCH_FIXTURE_VIDEO': str(folder / 'player.mp4'), 'WATCH_FIXTURE_BASE': f'http://127.0.0.1:{server.server_port}/'}


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
    media = scratch / 'media'
    media.mkdir()
    env = dict(os.environ, **media_fixtures(media))
    subprocess.run([str(binary), str(snapshots.resolve())], check=True, env=env)
