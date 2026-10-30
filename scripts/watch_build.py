#!/usr/bin/env python3
"""Standalone Watch build, test and DMG packaging. Never installs implicitly."""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import watch_helpers

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'scripts/app.json'

def run(command, capture=False):
    return subprocess.run([str(x) for x in command], check=True, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE if capture else None)


def say(message):
    print(message, flush=True)


def compile_binary(sources, executable, app, manifest, architectures, scratch):
    slices = []
    frameworks = [item for framework in app["frameworks"] for item in ("-framework", framework)]
    for architecture in architectures:
        output = scratch / (executable.name + "." + architecture)
        run(["xcrun", "swiftc", "-O", "-swift-version", manifest["swift_version"],
             "-target", architecture + "-apple-macos" + manifest["minimum_macos"],
             *sources, "-o", output, *frameworks])
        slices.append(output)
    if len(slices) == 1:
        shutil.copy2(slices[0], executable)
    else:
        run(["lipo", "-create", *slices, "-output", executable])


def publish_directory(staged, destination):
    """Replace only an explicit output, preserving it until the new copy is ready."""
    backup = destination.with_name(destination.name + ".previous")
    if backup.exists() or backup.is_symlink():
        raise ValueError("Previous replacement needs inspection: {}".format(backup))
    if destination.is_symlink():
        raise ValueError("Refusing to replace symlink: {}".format(destination))
    if destination.exists() and not destination.is_dir():
        raise ValueError("Refusing to replace non-directory: {}".format(destination))
    if destination.exists():
        destination.rename(backup)
    try:
        staged.rename(destination)
    except BaseException:
        if backup.exists():
            backup.rename(destination)
        raise
    if backup.exists():
        shutil.rmtree(backup)


def output_directory(path):
    # An old build/ or dist/ symlink must never redirect cleanup outside this repo.
    if path.resolve() != path:
        raise ValueError("Output path must not contain symlinks: {}".format(path))
    path.mkdir(parents=True, exist_ok=True)
    return path


def is_running(executable):
    result = subprocess.run(["pgrep", "-x", executable], stdout=subprocess.DEVNULL)
    if result.returncode not in (0, 1):
        raise ValueError("Could not determine whether {} is running".format(executable))
    return result.returncode == 0


def install_app(app, bundle):
    with (bundle / "Contents/Info.plist").open("rb") as stream:
        executable = plistlib.load(stream)["CFBundleExecutable"]
    if is_running(executable):
        raise ValueError("Quit {} before installing. No running app will be replaced.".format(app["name"]))
    applications = Path.home() / "Applications"
    applications.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".watch-install-", dir=applications) as temporary:
        staged = Path(temporary) / bundle.name
        run(["ditto", bundle, staged])
        run(["codesign", "--verify", "--deep", "--strict", staged], capture=True)
        if is_running(executable):
            raise ValueError("{} started during installation; quit it and retry.".format(app["name"]))
        destination = applications / bundle.name
        publish_directory(staged, destination)
    say("Installed {} (not launched)".format(destination))
    registrar = Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
    if registrar.is_file():
        result = subprocess.run([str(registrar), "-f", str(destination)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode:
            say("Warning: macOS did not refresh this app's URL handlers/Services; registration may require a new login.")


def validate_bundle(app, bundle, architectures, release=False):
    with (bundle / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    run(["plutil", "-lint", bundle / "Contents/Info.plist"], capture=True)
    executables = [info["CFBundleExecutable"]]
    for executable in executables:
        binary = bundle / "Contents/MacOS" / executable
        actual = set(run(["lipo", "-archs", binary], capture=True).stdout.split())
        if actual != set(architectures):
            raise ValueError("{}: expected {}, found {}".format(binary, architectures, sorted(actual)))
        run(["codesign", "--verify", "--strict", binary], capture=True)
    run(["codesign", "--verify", "--deep", "--strict", bundle], capture=True)
    watch_helpers.validate_helpers(bundle)
    if release:
        # Local signatures are useful for development, but are not public releases.
        signature = run(["codesign", "-d", "--verbose=4", bundle], capture=True).stderr
        if "Authority=Developer ID Application:" not in signature or "runtime" not in signature:
            raise ValueError("{} needs Developer ID signing with hardened runtime before release".format(app["name"]))
        run(["xcrun", "stapler", "validate", bundle])
        run(["spctl", "--assess", "--type", "execute", "--verbose=2", bundle])
    say("Verified {} ({})".format(bundle.relative_to(ROOT), ", ".join(architectures)))


def build_app(app, manifest, architectures, output, identity):
    directory, info = metadata(app)
    say("Building {} for {}".format(app["name"], ", ".join(architectures)))
    with tempfile.TemporaryDirectory(prefix=".stage-", dir=output) as temporary:
        scratch = Path(temporary)
        bundle = scratch / (app["name"] + ".app")
        macos = bundle / "Contents/MacOS"
        resources = bundle / "Contents/Resources"
        macos.mkdir(parents=True)
        resources.mkdir()
        sources = sorted((directory / "Sources").glob("*.swift"))
        compile_binary(sources, macos / info["CFBundleExecutable"], app, manifest, architectures, scratch)
        icon = directory / "AppIcon.icns"
        if icon.exists():
            shutil.copy2(icon, resources / icon.name)
        else:
            info.pop("CFBundleIconFile", None)
        with (bundle / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)
        watch_helpers.stage_helpers(bundle, identity)
        shutil.copy2(ROOT / "LICENSE", resources / "Watch-LICENSE.txt")
        run(["codesign", "--force", "--sign", identity, bundle])
        validate_bundle(app, bundle, architectures)
        destination = output / bundle.name
        publish_directory(bundle, destination)
    say("Built {}".format(destination))
    return destination


def package_app(app, bundle, destination):
    with tempfile.TemporaryDirectory(prefix=".package-", dir=destination) as temporary:
        scratch = Path(temporary)
        stage = scratch / app["name"]
        stage.mkdir()
        run(["ditto", bundle, stage / bundle.name])
        (stage / "Applications").symlink_to("/Applications")
        shutil.copy2(ROOT / "FIRST_RUN.txt", stage / "Read Me.txt")
        # The release number is in the file name (Watch-3.24.dmg); the volume is still just "Watch".
        version = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
        dmg = scratch / "{}-{}.dmg".format(app["name"], version)
        run(["hdiutil", "create", "-volname", app["name"], "-srcfolder", stage,
             "-format", "UDZO", dmg], capture=True)
        run(["hdiutil", "verify", dmg], capture=True)
        final = destination / dmg.name
        if final.is_symlink():
            raise ValueError("Refusing to replace symlink: {}".format(final))
        os.replace(dmg, final)
    say("Packaged {} (local preview; not notarized)".format(final))


def metadata(config):
    with (ROOT / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    for key in ('CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleShortVersionString', 'CFBundleVersion'):
        if not info.get(key):
            raise ValueError('Missing metadata: ' + key)
    if info['CFBundleName'] != config['name'] or not info.get('LSUIElement'):
        raise ValueError('Invalid Watch metadata')
    if info['CFBundleExecutable'] != 'Watch' or config['name'] != 'Watch':
        raise ValueError('Invalid Watch executable metadata')
    if info['LSMinimumSystemVersion'] != config['minimum_macos']:
        raise ValueError('Minimum macOS differs from scripts/app.json')
    if not (ROOT / 'Sources/main.swift').is_file():
        raise ValueError('Missing Watch entrypoint')
    if not config['frameworks'] or len(config['frameworks']) != len(set(config['frameworks'])):
        raise ValueError('Invalid framework list')
    return ROOT, info


def check_sources(config):
    _, info = metadata(config)
    run(['plutil', '-lint', ROOT / 'Info.plist'], capture=True)
    for script in sorted(ROOT.glob('*.sh')) + sorted((ROOT / 'scripts').glob('*.sh')):
        run(['bash', '-n', script])
    say('Checked Watch {} ({})'.format(info['CFBundleShortVersionString'], info['CFBundleVersion']))


def run_tests():
    run([sys.executable, ROOT / 'scripts/test_tooling.py'])
    run(['bash', ROOT / 'test.sh'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('build', 'check', 'package'))
    parser.add_argument('--universal', action='store_true', help='Build both architectures; package always does')
    parser.add_argument('--install', action='store_true', help='Explicitly replace ~/Applications/Watch.app after quitting it; never launch')
    parser.add_argument('--identity', help='Optional signing identity; defaults to local ad-hoc signing')
    parser.add_argument('--built', action='store_true', help='Check the existing built bundle as well as source/tests')
    parser.add_argument('--release', action='store_true', help='Also require Developer ID, hardened runtime and notarization')
    args = parser.parse_args()
    if args.install and args.command != 'build':
        parser.error('--install is only valid with build')
    if (args.built or args.release) and args.command != 'check':
        parser.error('--built and --release require check')
    if args.identity and args.command == 'check':
        parser.error('--identity applies to build/package')
    config = json.loads(CONFIG.read_text())
    check_sources(config)
    universal = args.universal or args.command == 'package'
    architectures = ['arm64', 'x86_64'] if universal else [platform.machine()]
    if any(a not in ('arm64', 'x86_64') for a in architectures):
        raise ValueError('Watch requires an Apple Silicon or Intel Mac')
    output = ROOT / 'build' / ('universal' if universal else 'native')
    if args.command == 'check':
        run_tests()
        if args.built or args.release:
            validate_bundle(config, output / 'Watch.app', architectures, args.release)
        return
    if args.command == 'package':
        run_tests()
    output_directory(output)
    identity = args.identity or '-'
    say('Signing: ' + ('ad-hoc (local only)' if identity == '-' else identity))
    bundle = build_app(config, config, architectures, output, identity)
    if args.install:
        install_app(config, bundle)
    if args.command == 'package':
        package_app(config, bundle, output_directory(ROOT / 'dist'))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('error: {}'.format(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
