#!/usr/bin/env python3
"""Real bundled helpers, isolated HOME, generated media, no account/cookie access."""
import functools
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
helpers = Path(sys.argv[1]).resolve()
contents = helpers.parent                  # the built app's Contents (Now Playing adapter lives beside Helpers)
live = '--live' in sys.argv[2:]
checks = 0

def check(value, message):
    global checks
    assert value, message
    checks += 1
    print('PASS ' + message, flush=True)

with tempfile.TemporaryDirectory(prefix='Watch clean install ') as temp:
    home = Path(temp)
    relocated = home / 'Relocated App.app/Contents/Helpers'
    shutil.copytree(helpers, relocated)
    helpers = relocated
    env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(home), 'TMPDIR': str(home),
           'XDG_CONFIG_HOME': str(home / '.config'), 'XDG_CACHE_HOME': str(home / '.cache'),
           'DENO_DIR': str(home / 'deno'), 'DENO_NO_UPDATE_CHECK': '1'}
    def run(args, timeout=90):
        result = subprocess.run([str(a) for a in args], env=env, cwd=home, capture_output=True, text=True, timeout=timeout)
        if result.returncode:
            raise AssertionError(f'{args[0]} returned {result.returncode}: {result.stderr[-3000:]}')
        return result.stdout
    shutil.copy2(ROOT / 'Tests/MediaToolsMain.swift', home / 'main.swift')
    subprocess.run(['xcrun', 'swiftc', str(ROOT / 'Sources/MediaTools.swift'), str(home / 'main.swift'), '-o', str(home / 'boundary')], check=True)
    boundary = [home / 'boundary', helpers]
    check(run(boundary + ['check']).count(': true ') == 4, 'production readiness check runs all four relocated tools')
    config = home / '.config/yt-dlp/config'; config.parent.mkdir(parents=True)
    config.write_text('--invalid-configuration-must-be-ignored\n')
    check(run(boundary + ['--version']).strip() == '2026.10.26', 'bundled Python works without Python/PATH or host configuration')
    check(run([helpers / 'deno', 'eval', 'console.log(6 * 7)']).strip() == '42', 'bundled JavaScript runtime executes offline')
    ffmpeg, probe = helpers / 'ffmpeg', helpers / 'ffprobe'
    source = home / 'fixture.mp4'
    run([ffmpeg, '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=12', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '1', '-c:v', 'mpeg4', '-c:a', 'aac', source])
    check(source.stat().st_size > 1000, 'FFmpeg generates synthetic video/audio')
    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args): pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(home)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_port}/fixture.mp4'
    try:
        run(boundary + ['--no-playlist', '-x', '--audio-format', 'mp3', '-o', str(home / 'download.%(ext)s'), url])
        info = json.loads(run([probe, '-v', 'error', '-show_streams', '-of', 'json', home / 'download.mp3']))
        check(info['streams'][0]['codec_name'] == 'mp3', 'real yt-dlp download invokes bundled FFmpeg and LAME for MP3')
        run([ffmpeg, '-v', 'error', '-i', source, '-c:v', 'hevc_videotoolbox', '-b:v', '1000k', '-tag:v', 'hvc1', '-c:a', 'aac', home / 'converted.mp4'])
        converted = json.loads(run([probe, '-v', 'error', '-show_streams', '-of', 'json', home / 'converted.mp4']))
        check(converted['streams'][0]['codec_name'] == 'hevc', 'MP4 conversion uses the same VideoToolbox encoder as Watch')
        run([ffmpeg, '-v', 'error', '-i', source, '-an', '-c:v', 'copy', home / 'video.mp4'])
        run([ffmpeg, '-v', 'error', '-i', source, '-vn', '-c:a', 'copy', home / 'audio.m4a'])
        run([ffmpeg, '-v', 'error', '-i', home / 'video.mp4', '-i', home / 'audio.m4a', '-c', 'copy', home / 'merged.mp4'])
        info = json.loads(run([probe, '-v', 'error', '-show_streams', '-of', 'json', home / 'merged.mp4']))
        check({s['codec_type'] for s in info['streams']} == {'video', 'audio'}, 'bundled tools merge separate video and audio tracks')
    finally:
        server.shutdown(); server.server_close()
    rosetta = subprocess.run(['/usr/bin/arch', '-x86_64', '/usr/bin/true'], capture_output=True).returncode == 0
    if rosetta:
        for name in ('yt-dlp', 'ffmpeg', 'ffprobe', 'deno'):
            output = run(['/usr/bin/arch', '-x86_64', helpers / name, '-version' if name in ('ffmpeg', 'ffprobe') else '--version'])
            check(bool(output.strip()), name + ' Intel slice executes under Rosetta')
    else:
        print('SKIP Intel execution: Rosetta unavailable', flush=True)
    # Now Playing: the adapter from a relocated path with spaces, under system perl, clean environment. Read-only
    # `get` only (never `test`, which registers a fake player, nor any playback command).
    relocated_contents = home / 'Relocated App.app/Contents'
    adapter_framework = relocated_contents / 'Frameworks/MediaRemoteAdapter.framework'
    shutil.copytree(contents / 'Frameworks/MediaRemoteAdapter.framework', adapter_framework, symlinks=True)
    adapter_script = relocated_contents / 'Resources/NowPlaying/mediaremote-adapter.pl'
    adapter_script.parent.mkdir(parents=True)
    shutil.copy2(contents / 'Resources/NowPlaying/mediaremote-adapter.pl', adapter_script)
    state = json.loads(run(['/usr/bin/perl', adapter_script, adapter_framework, 'get', '--no-artwork'], timeout=30))
    check(state is None or 'bundleIdentifier' in state, 'Now Playing adapter loads under system perl and reads MediaRemote')
    print('Now Playing: ' + json.dumps(state and {k: state.get(k) for k in ('bundleIdentifier', 'title', 'playing')}), flush=True)
    if live:
        result = json.loads(run(boundary + ['--flat-playlist', '--dump-single-json', '--skip-download', '--socket-timeout', '15', '--retries', '0', 'ytsearch3:NASA official'], timeout=60))
        check(len(result['entries']) == 3, 'live public YouTube search works without cookies or sign-in')
        print('Public search titles: ' + json.dumps([v.get('title') for v in result['entries']]), flush=True)
        video_url = 'https://www.youtube.com/watch?v=' + result['entries'][0]['id']
        metadata = json.loads(run(boundary + ['--dump-single-json', '--skip-download', '--no-playlist', '--socket-timeout', '15', '--retries', '0', '-f', 'bv*[vcodec^=avc1][height<=1080][protocol=https]+ba[ext=m4a][protocol=https]/b[protocol^=m3u8]/b[ext=mp4]/bv*+ba/b', video_url], timeout=90))
        check(bool(metadata.get('formats')), 'live public video metadata resolves with bundled EJS and Deno available')
    print(f'Watch bundled integration: {checks} checks passed', flush=True)
