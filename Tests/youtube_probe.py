#!/usr/bin/env python3
"""Diagnostic: the player's YouTube pipeline on real links (resolveStream → plans → DashHLSBridge → AVPlayer), with
the bundled helpers, reporting each step — formats, each file's sidx, playlist sizes, and whether playback starts and
keeps going at the start, middle and near the end. Informational; YouTube can bot-check data-centre addresses.
Run: python3 Tests/youtube_probe.py <Helpers directory> <link>...
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
helpers = pathlib.Path(sys.argv[1]).resolve()
links = sys.argv[2:]
app = json.loads((root / 'scripts/app.json').read_text())
HOURS = [3, 10]   # fixture lengths: a long video, and one whose sidx no longer fits the bridge's first 64 KB read


class RangeHandler(http.server.SimpleHTTPRequestHandler):
    """Static files with HTTP byte ranges, as YouTube's CDN serves them (the query string is ignored)."""
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


def fixtures(folder):
    """Hours-long renditions laid out like YouTube's (ftyp, moov, one sidx, moof/mdat): video in 5 s fragments, audio in 10 s."""
    ffmpeg = str(helpers / 'ffmpeg')
    names = []
    for hours in HOURS:
        seconds = str(hours * 3600)
        jobs = {
            f'v{hours}h.mp4': ['-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=1', '-t', seconds, '-c:v', 'h264_videotoolbox', '-b:v', '30k',
                               '-g', '5', '-an', '-movflags', '+frag_keyframe+empty_moov+default_base_moof+global_sidx'],
            f'a{hours}h.m4a': ['-f', 'lavfi', '-i', 'sine=frequency=330:sample_rate=8000', '-t', seconds, '-c:a', 'aac', '-b:a', '16k',
                               '-ac', '1', '-vn', '-frag_duration', '10000000', '-movflags', '+empty_moov+default_base_moof+global_sidx'],
        }
        made = True
        for name, args in jobs.items():
            result = subprocess.run([ffmpeg, '-v', 'error', '-y', *args, str(folder / name)], capture_output=True, text=True)
            if result.returncode != 0:
                print(f'fixture {name}: FFmpeg failed: {result.stderr[-400:]}', flush=True)
                made = False
            else:
                print(f'fixture {name}: {(folder / name).stat().st_size / 1048576:.1f} MB', flush=True)
        if made:
            names.append(f'{hours}h')
    if not names:
        return {}
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(RangeHandler, directory=str(folder)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return {'WATCH_PROBE_FIXTURES': '|'.join([f'http://127.0.0.1:{server.server_port}/'] + names)}


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
    media = scratch / 'media'
    media.mkdir()
    env = dict(os.environ, HOME=str(home), TMPDIR=str(scratch), **fixtures(media))
    sys.exit(subprocess.run([str(binary), *links], env=env, cwd=scratch, timeout=1500).returncode)
