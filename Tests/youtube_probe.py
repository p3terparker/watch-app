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
HOURS = [3]   # 3.27 probe: 3 h and 10 h both played; 10 h (sidx past 64 KB, 8.8 MB playlists) is covered


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


def boxes(data):
    out, offset = [], 0
    while offset + 8 <= len(data):
        size = int.from_bytes(data[offset:offset + 4], 'big')
        if size < 8:
            break
        out.append((data[offset + 4:offset + 8].decode('latin-1'), offset, size))
        offset += size
    return out


def beyond_4gb(source, target):
    """The same rendition with its media moved past byte 4 GB (a sparse hole after the sidx, its first_offset moved to
    match), like a 2-3 hour 1080p60 YouTube file."""
    data = source.read_bytes()
    _, offset, size = next(b for b in boxes(data[:1 << 20]) if b[0] == 'sidx')
    assert data[offset + 8] == 0, 'version 0 sidx expected'
    field = offset + 8 + 4 + 4 + 4 + 4                                   # version/flags, reference_ID, timescale, earliest_pt
    gap = 0xFFFF0000
    first = int.from_bytes(data[field:field + 4], 'big') + gap
    assert first < 1 << 32
    with open(target, 'wb') as f:
        f.write(data[:field] + first.to_bytes(4, 'big') + data[field + 4:offset + size])
        f.seek(offset + size + gap)
        f.write(data[offset + size:])


def fixtures(folder):
    """Hours-long renditions laid out like YouTube's (ftyp, moov, one sidx, moof/mdat): video in 5 s fragments, audio in 10 s."""
    ffmpeg = str(helpers / 'ffmpeg')
    sets = []
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
            sets.append(f'{hours}h,v{hours}h.mp4,a{hours}h.m4a,800')
    if (folder / 'v3h.mp4').exists():
        sets.append('3h declared below its real bit rate,v3h.mp4,a3h.m4a,8')
        try:
            beyond_4gb(folder / 'v3h.mp4', folder / 'vbig.mp4')
            print(f'fixture vbig.mp4: {(folder / "vbig.mp4").stat().st_size / 1e9:.2f} GB (sparse)', flush=True)
            sets.append('3h past 4 GB,vbig.mp4,a3h.m4a,800')
        except Exception as error:
            print(f'fixture vbig.mp4: {error!r}', flush=True)
    if not sets:
        return {}
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(RangeHandler, directory=str(folder)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return {'WATCH_PROBE_FIXTURES': f'http://127.0.0.1:{server.server_port}/|' + ';'.join(sets)}


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
