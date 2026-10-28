#!/usr/bin/env python3
"""Pinned, relocatable Watch helper bundle. Build-time only; never installs system tools."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
LOCK = ROOT / 'Dependencies.json'
CACHE = ROOT / 'build/watch-vendor'
PAYLOAD = CACHE / 'payload'
TOOLS = ('yt-dlp', 'ffmpeg', 'ffprobe', 'deno')
BUILD_REVISION = 'ffmpeg-lgpl-static-macos13-v1'
# Now Playing (Sources/NowPlaying.swift): mediaremote-adapter, built from a pinned commit into its own cache, so a
# change to it never rebuilds FFmpeg. Watch only ever runs its read-only `stream` command.
ADAPTER = 'mediaremote-adapter'
ADAPTER_REVISION = 'mediaremote-adapter-universal-macos13-v1'
ADAPTER_FRAMEWORK = 'MediaRemoteAdapter.framework'
ADAPTER_BINARY = 'Versions/A/MediaRemoteAdapter'
ADAPTER_ID = '@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter'
ADAPTER_SCRIPT = 'mediaremote-adapter.pl'
# Upstream CMakeLists.txt ADAPTER_SOURCES (the test client is not built).
ADAPTER_SOURCES = ('src/adapter/env.m', 'src/adapter/get.m', 'src/adapter/globals.m', 'src/adapter/keys.m',
                   'src/adapter/now_playing.m', 'src/adapter/repeat.m', 'src/adapter/seek.m', 'src/adapter/send.m',
                   'src/adapter/shuffle.m', 'src/adapter/speed.m', 'src/adapter/stream.m', 'src/adapter/test.m',
                   'src/private/MediaRemote.m', 'src/utility/Debounce.m', 'src/utility/helpers.m')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fetch(name, item):
    path = CACHE / name
    if path.exists():
        if digest(path) != item['sha256']:
            raise ValueError('Checksum mismatch in cached helper input: ' + name)
        return path
    with tempfile.NamedTemporaryFile(dir=CACHE, prefix='.download-', delete=False) as stream:
        temporary = Path(stream.name)
        try:
            request = urllib.request.Request(item['url'], headers={'User-Agent': 'Watch-build'})
            with urllib.request.urlopen(request, timeout=120) as response:
                shutil.copyfileobj(response, stream)
            stream.close()
            if digest(temporary) != item['sha256']:
                raise ValueError('Downloaded helper checksum mismatch: ' + name)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    return path


def fetch_source(name, item):
    """A pinned commit of a source-only dependency, as a tar archive. Git checks every object against the commit hash."""
    archive = CACHE / f'{name}-{item["commit"]}.tar'
    if archive.exists():
        with archive.open('rb') as stream:
            embedded = subprocess.run(['git', 'get-tar-commit-id'], stdin=stream, capture_output=True, text=True).stdout.strip()
        if embedded != item['commit']:
            raise ValueError('Cached source archive is not the pinned commit: ' + archive.name)
        return archive
    with tempfile.TemporaryDirectory(prefix='.git-', dir=CACHE) as work:
        run(['git', 'init', '-q', work], capture_output=True)
        run(['git', '-C', work, 'fetch', '-q', '--depth', '1', item['url'], item['commit']])
        fetched = run(['git', '-C', work, 'rev-parse', 'FETCH_HEAD^{commit}'], capture_output=True, text=True).stdout.strip()
        if fetched != item['commit']:
            raise ValueError(f'{name}: fetched {fetched}, expected {item["commit"]}')
        temporary = Path(work) / 'source.tar'
        run(['git', '-C', work, 'archive', '--format=tar', f'--prefix={name}/', '-o', temporary, item['commit']])
        temporary.replace(archive)
    return archive


def helper_inputs(manifest):
    # FFmpeg/yt-dlp/Deno inputs only: the cached payload's fingerprint ignores pinned sources (Now Playing).
    return {key: value for key, value in manifest.items() if key != 'sources'}


def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def inspect_binary(path, expected=('arm64', 'x86_64'), own_id=None):
    archs = run(['lipo', '-archs', path], capture_output=True, text=True).stdout.split()
    if set(archs) != set(expected):
        raise ValueError(f'{path}: wrong architectures: {archs}')
    dependencies = run(['otool', '-L', path], capture_output=True, text=True).stdout
    for line in dependencies.splitlines():
        if line.startswith('\t'):
            dependency = line.strip().split(' (')[0]
            if dependency == own_id:
                continue    # a dylib lists its own install name first
            if not dependency.startswith(('/usr/lib/', '/System/Library/')):
                raise ValueError(f'{path}: non-system library dependency {dependency}')
    loads = run(['otool', '-l', path], capture_output=True, text=True).stdout.splitlines()
    command = ''
    for line in loads:
        bits = line.strip().split()
        if len(bits) == 2 and bits[0] == 'cmd':
            command = bits[1]
        if len(bits) == 2 and bits[0] in ('minos', 'version'):
            # LC_BUILD_VERSION uses minos. Older LC_VERSION_MIN_MACOSX uses version.
            if (bits[0] == 'minos' or command == 'LC_VERSION_MIN_MACOSX') and tuple((list(map(int, bits[1].split('.'))) + [0, 0])[:3]) > (13, 0, 0):
                raise ValueError(f'{path}: deployment target exceeds macOS 13: {bits[1]}')


def build_ffmpeg(arch, dest):
    log = CACHE / f'build-{arch}.log'
    with tempfile.TemporaryDirectory(prefix=f'watch-ffmpeg-{arch}-', dir='/private/tmp') as work:
        work = Path(work)
        with log.open('w') as output:
            env = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin', MACOSX_DEPLOYMENT_TARGET='13.0')
            def command(args, cwd):
                output.write('COMMAND ' + repr([str(a) for a in args]) + '\n'); output.flush()
                run(args, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT)
            try:
                command(['tar', '-xf', CACHE / 'lame-3.100.tar.gz'], work)
                command(['tar', '-xf', CACHE / 'ffmpeg-9.0.2.tar.xz'], work)
                prefix = work / 'prefix'
                cc = f'/usr/bin/clang -arch {arch} -mmacosx-version-min=13.0'
                env.update(CC=cc, CFLAGS='-O2 -Wno-error=implicit-function-declaration', LDFLAGS=f'-arch {arch} -mmacosx-version-min=13.0')
                lame = work / 'lame-3.100'
                command(['./configure', f'--prefix={prefix}', '--disable-shared', '--enable-static',
                         '--disable-frontend', '--disable-dependency-tracking',
                         f'--host={"aarch64" if arch == "arm64" else arch}-apple-darwin'], lame)
                command(['make', '-j4'], lame)
                command(['make', 'install'], lame)
                ffmpeg = work / 'ffmpeg-9.0.2'
                command(['./configure', '--target-os=darwin', f'--arch={"aarch64" if arch == "arm64" else arch}',
                         '--enable-cross-compile', f'--cc={cc}', '--pkg-config=/usr/bin/false',
                         '--disable-autodetect', '--disable-doc', '--disable-debug', '--disable-shared',
                         '--enable-static', '--disable-ffplay', '--disable-x86asm',
                         '--enable-videotoolbox', '--enable-audiotoolbox', '--enable-securetransport',
                         '--enable-zlib', '--enable-libmp3lame',
                         f'--extra-cflags=-I{prefix}/include',
                         f'--extra-ldflags=-L{prefix}/lib -mmacosx-version-min=13.0'], ffmpeg)
                command(['make', '-j4', 'ffmpeg', 'ffprobe'], ffmpeg)
                for name in ('ffmpeg', 'ffprobe'):
                    shutil.copy2(ffmpeg / name, dest / f'{name}-{arch}')
                shutil.copy2(ffmpeg / 'config.h', dest / f'ffmpeg-config-{arch}.h')
                shutil.copy2(ffmpeg / 'ffbuild/config.mak', dest / f'ffmpeg-config-{arch}.mak')
                shutil.copy2(ffmpeg / 'COPYING.LGPLv2.1', dest / 'FFmpeg-LICENSE.txt')
                shutil.copy2(lame / 'COPYING', dest / 'LAME-LICENSE.txt')
            except Exception:
                print(log.read_text()[-6500:], flush=True)
                raise


def prepare():
    CACHE.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(LOCK.read_text())
    for name, item in manifest['downloads'].items():
        fetch(name, item)
    fingerprint = hashlib.sha256((BUILD_REVISION + json.dumps(helper_inputs(manifest), sort_keys=True)).encode()).hexdigest()
    receipt = PAYLOAD / 'receipt.json'
    if receipt.exists():
        saved = json.loads(receipt.read_text())
        if saved['fingerprint'] == fingerprint:
            for name, expected in saved['hashes'].items():
                if digest(PAYLOAD / name) != expected:
                    raise ValueError('Prepared helper changed: ' + name)
            return PAYLOAD
    with tempfile.TemporaryDirectory(prefix='.payload-', dir=CACHE) as temp:
        stage = Path(temp)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            tasks = [pool.submit(build_ffmpeg, arch, stage) for arch in ('arm64', 'x86_64')]
            for task in tasks:
                task.result()
        tools = stage / 'Helpers'; tools.mkdir()
        for name in ('ffmpeg', 'ffprobe'):
            run(['lipo', '-create', stage / f'{name}-arm64', stage / f'{name}-x86_64', '-output', tools / name])
        for arch in ('arm64', 'x86_64'):
            with zipfile.ZipFile(CACHE / f'deno-{arch}.zip') as archive:
                (stage / f'deno-{arch}').write_bytes(archive.read('deno'))
        run(['lipo', '-create', stage / 'deno-arm64', stage / 'deno-x86_64', '-output', tools / 'deno'])
        shutil.copy2(CACHE / 'yt-dlp_macos', tools / 'yt-dlp')
        for name in TOOLS:
            path = tools / name
            path.chmod(0o755)
            inspect_binary(path)
            run(['codesign', '--force', '--sign', '-', path], capture_output=True)
        thirdparty = stage / 'ThirdParty'; thirdparty.mkdir()
        sources = thirdparty / 'Sources'; sources.mkdir()
        for name in manifest['downloads']:
            if name.endswith(('.tar.gz', '.tar.xz')):
                shutil.copy2(CACHE / name, sources / name)
            elif name.endswith('.txt'):
                shutil.copy2(CACHE / name, thirdparty / name)
        for name in ('FFmpeg-LICENSE.txt', 'LAME-LICENSE.txt'):
            shutil.move(str(stage / name), thirdparty / name)
        for path in stage.glob('ffmpeg-config-*'):
            shutil.move(str(path), sources / path.name)
        with tarfile.open(CACHE / 'deno-source.tar.gz') as archive:
            notices = []
            for member in archive.getmembers():
                if member.isfile() and 'LICENSE' in Path(member.name).name and '/tests/' not in member.name:
                    notices.append(member.name + '\n' + archive.extractfile(member).read().decode('utf-8'))
            (thirdparty / 'deno-THIRD-PARTY.txt').write_text('\n\n'.join(notices))
        shutil.copy2(LOCK, thirdparty / 'Dependencies.json')
        shutil.copy2(__file__, sources / 'watch_helpers.py')
        (thirdparty / 'README.txt').write_text(
            'Watch media tools are independent executables, invoked as child processes.\n'
            'yt-dlp: official macOS standalone release, GPLv3+ as a bundled executable; upstream notices included.\n'
            'FFmpeg: built from the included source, LGPLv2.1+, with static LAME (LGPLv2+), '
            'Apple system frameworks, no GPL/nonfree configuration or Homebrew libraries.\n'
            'Deno: official macOS releases combined into a universal executable; MIT and third-party notices included.\n'
            'Source archives, FFmpeg build configuration and build recipe are in Sources. '
            'Dependencies.json records pinned source URLs and SHA-256 hashes.\n'
            'Helpers are updated by replacing Watch with a newer app. They never self-modify this bundle.\n'
            'mediaremote-adapter (Now Playing): built from the included pinned source archive (BSD-3-Clause, notice included) '
            'into Contents/Frameworks/MediaRemoteAdapter.framework; its perl entry script is in Contents/Resources/NowPlaying.\n')
        hashes = {str(p.relative_to(stage)): digest(p) for p in stage.rglob('*') if p.is_file()
                  and (p.is_relative_to(tools) or p.is_relative_to(thirdparty))}
        (stage / 'receipt.json').write_text(json.dumps(dict(fingerprint=fingerprint, versions=manifest['versions'], hashes=hashes), indent=2))
        if PAYLOAD.exists():
            # Only generated cache, after a complete replacement has been prepared.
            shutil.rmtree(PAYLOAD)
        PAYLOAD.mkdir()
        for name in ('Helpers', 'ThirdParty', 'receipt.json'):
            shutil.move(str(stage / name), PAYLOAD / name)
    return PAYLOAD


def build_now_playing(archive, stage):
    """Universal MediaRemoteAdapter.framework + its perl entry script, as upstream's CMake would build them."""
    with tempfile.TemporaryDirectory(prefix='watch-nowplaying-', dir='/private/tmp') as work:
        work = Path(work)
        run(['tar', '-xf', archive], cwd=work)
        source = work / ADAPTER
        framework = stage / ADAPTER_FRAMEWORK
        version = framework / 'Versions/A'
        (version / 'Resources').mkdir(parents=True)
        env = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin', MACOSX_DEPLOYMENT_TARGET='13.0')
        run(['/usr/bin/clang', '-arch', 'arm64', '-arch', 'x86_64', '-mmacosx-version-min=13.0', '-O2',
             '-fobjc-arc', '-fvisibility=default', '-dynamiclib', '-install_name', ADAPTER_ID,
             '-compatibility_version', '0.1.0', '-current_version', '0.1.0',
             '-I', source / 'include', '-I', source / 'src', *[source / name for name in ADAPTER_SOURCES],
             '-framework', 'Foundation', '-framework', 'AppKit', '-framework', 'UniformTypeIdentifiers',
             '-o', framework / ADAPTER_BINARY], env=env)
        with (version / 'Resources/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleDevelopmentRegion': 'en', 'CFBundleExecutable': 'MediaRemoteAdapter',
                           'CFBundleIdentifier': 'com.vandenbe.MediaRemoteAdapter', 'CFBundleInfoDictionaryVersion': '6.0',
                           'CFBundleName': 'MediaRemoteAdapter', 'CFBundlePackageType': 'FMWK',
                           'CFBundleShortVersionString': '0.1', 'CFBundleVersion': '0.1.0',
                           'LSMinimumSystemVersion': '13.0'}, stream)
        (framework / 'Versions/Current').symlink_to('A')
        (framework / 'MediaRemoteAdapter').symlink_to('Versions/Current/MediaRemoteAdapter')
        (framework / 'Resources').symlink_to('Versions/Current/Resources')
        shutil.copy2(source / 'bin' / ADAPTER_SCRIPT, stage / ADAPTER_SCRIPT)
        shutil.copy2(source / 'LICENSE', stage / f'{ADAPTER}-LICENSE.txt')


def prepare_now_playing():
    CACHE.mkdir(parents=True, exist_ok=True)
    item = json.loads(LOCK.read_text())['sources'][ADAPTER]
    archive = fetch_source(ADAPTER, item)
    target = CACHE / 'nowplaying'
    fingerprint = hashlib.sha256((ADAPTER_REVISION + json.dumps(item, sort_keys=True)).encode()).hexdigest()
    receipt = target / 'receipt.json'
    if receipt.exists():
        saved = json.loads(receipt.read_text())
        if saved['fingerprint'] == fingerprint:
            for name, expected in saved['hashes'].items():
                if digest(target / name) != expected:
                    raise ValueError('Prepared Now Playing adapter changed: ' + name)
            return target, archive
    with tempfile.TemporaryDirectory(prefix='.nowplaying-', dir=CACHE) as temp:
        stage = Path(temp)
        build_now_playing(archive, stage)
        inspect_binary(stage / ADAPTER_FRAMEWORK / ADAPTER_BINARY, own_id=ADAPTER_ID)
        run(['codesign', '--force', '--sign', '-', stage / ADAPTER_FRAMEWORK], capture_output=True)
        hashes = {str(p.relative_to(stage)): digest(p) for p in stage.rglob('*') if p.is_file() and not p.is_symlink()}
        (stage / 'receipt.json').write_text(json.dumps(dict(fingerprint=fingerprint, commit=item['commit'], hashes=hashes), indent=2))
        if target.exists():
            shutil.rmtree(target)     # only generated cache, after a complete replacement has been prepared
        shutil.copytree(stage, target, symlinks=True)
    return target, archive


def stage_now_playing(bundle, identity):
    """Framework in Contents/Frameworks (signed before the app), script in Contents/Resources/NowPlaying."""
    prepared, archive = prepare_now_playing()
    framework = bundle / 'Contents/Frameworks' / ADAPTER_FRAMEWORK
    framework.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(prepared / ADAPTER_FRAMEWORK, framework, symlinks=True)
    script = bundle / 'Contents/Resources/NowPlaying' / ADAPTER_SCRIPT
    script.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(prepared / ADAPTER_SCRIPT, script)
    thirdparty = bundle / 'Contents/Resources/ThirdParty'
    shutil.copy2(prepared / f'{ADAPTER}-LICENSE.txt', thirdparty / f'{ADAPTER}-LICENSE.txt')
    shutil.copy2(archive, thirdparty / 'Sources' / archive.name)
    run(['codesign', '--force', '--sign', identity, framework], capture_output=True)
    commit = json.loads(LOCK.read_text())['sources'][ADAPTER]['commit']
    return dict(commit=commit, sha256=dict(framework=digest(framework / ADAPTER_BINARY), script=digest(script)))


def stage_helpers(bundle, identity):
    payload = prepare()
    helpers = bundle / 'Contents/Helpers'
    shutil.copytree(payload / 'Helpers', helpers)
    resources = bundle / 'Contents/Resources'
    shutil.copytree(payload / 'ThirdParty', resources / 'ThirdParty')
    for name in TOOLS:
        run(['codesign', '--force', '--sign', identity, helpers / name], capture_output=True)
    supplemental = ROOT / 'SupplementalSources.json'
    for name, item in json.loads(supplemental.read_text()).items():
        shutil.copy2(fetch(name, item), resources / 'ThirdParty/Sources' / name)
    shutil.copy2(supplemental, resources / 'ThirdParty/SupplementalSources.json')
    shutil.copy2(__file__, resources / 'ThirdParty/Sources/watch_helpers.py')
    (resources / 'ThirdParty/Sources/BUILDING.txt').write_text(
        'Reproduce the helper build on a Mac with Xcode command line tools and Python 3.9+:\n'
        'Create a working directory with scripts/ and build/watch-vendor/.\n'
        'Place watch_helpers.py in scripts/, Dependencies.json and SupplementalSources.json at the working directory root.\n'
        'Place the included archives in build/watch-vendor/ with their existing filenames.\n'
        'Run python3 scripts/watch_helpers.py; additional pinned upstream binaries are downloaded and hash-checked.\n'
        'The script records the exact FFmpeg/LAME configure and compiler arguments; original generated configurations are also included.\n'
        'The FFmpeg and LAME sources are unmodified. You may rebuild, modify and replace the independent helper executables;\n'
        'a modified app needs its signature recreated for macOS. Watch does not prohibit modified helper builds.\n'
        'yt-dlp source includes its PyInstaller build recipe; upstream bundled component notices and source contact are in yt-dlp-LICENSES.txt.\n'
        'MediaRemoteAdapter.framework is rebuilt from mediaremote-adapter-<commit>.tar (the commit pinned in Dependencies.json \"sources\");\n'
        'place that archive in build/watch-vendor/ too.\n')
    now_playing = stage_now_playing(bundle, identity)
    versions = json.loads(LOCK.read_text())['versions']
    receipt = dict(versions=versions, sha256={name: digest(helpers / name) for name in TOOLS}, nowPlaying=now_playing)
    (resources / 'MediaTools.json').write_text(json.dumps(receipt, indent=2) + '\n')


def validate_helpers(bundle):
    receipt = json.loads((bundle / 'Contents/Resources/MediaTools.json').read_text())
    for name in TOOLS:
        path = bundle / 'Contents/Helpers' / name
        if digest(path) != receipt['sha256'][name]:
            raise ValueError('Bundled helper checksum mismatch: ' + name)
        inspect_binary(path)
        run(['codesign', '--verify', '--strict', path], capture_output=True)
    if not (bundle / 'Contents/Resources/ThirdParty/Sources/ffmpeg-9.0.2.tar.xz').is_file():
        raise ValueError('Missing helper source bundle')
    framework = bundle / 'Contents/Frameworks' / ADAPTER_FRAMEWORK
    script = bundle / 'Contents/Resources/NowPlaying' / ADAPTER_SCRIPT
    now = receipt['nowPlaying']
    if digest(framework / ADAPTER_BINARY) != now['sha256']['framework'] or digest(script) != now['sha256']['script']:
        raise ValueError('Bundled Now Playing adapter checksum mismatch')
    inspect_binary(framework / ADAPTER_BINARY, own_id=ADAPTER_ID)
    run(['codesign', '--verify', '--strict', framework], capture_output=True)
    if not (bundle / 'Contents/Resources/ThirdParty/Sources' / f'{ADAPTER}-{now["commit"]}.tar').is_file():
        raise ValueError('Missing Now Playing adapter source')


if __name__ == '__main__':
    print(prepare())
    print(prepare_now_playing()[0])
