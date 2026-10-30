#!/bin/bash
# watch-update — replace the Watch on this Mac with the newest build from GitHub, in one command.
#
#   watch-update              the newest passing build (the "Current build" pre-release)
#   watch-update --stable     the release marked Latest instead
#   watch-update --dry-run    say what it would do; change nothing
#   watch-update --force      reinstall even if this build is already installed
#   watch-update --uninstall-agent  remove the 10-minute background checker an earlier version of this script could install
#
# It runs only when you ask (or when Claude has just finished a wave of changes and runs it for you): it does not check on a
# schedule. Run it straight from GitHub so there is never an old copy: curl -fsSL <raw URL of this file> | bash
#
# Why it avoids the "unidentified developer" dialog and the password: the disk image is fetched with curl, which does not
# mark it as quarantined (a browser download does), so Gatekeeper never looks at it; and Watch is replaced where it already
# lives (/Applications is writable by admin users; otherwise ~/Applications, which is yours). Settings are in your user
# preferences, so they stay. Needs only what macOS ships: bash, curl, hdiutil, ditto, shasum, osascript.
#
# Override with environment variables: WATCH_REPO (default p3terparker/watch-app), WATCH_DEST (the .app to replace).
set -euo pipefail

REPO="${WATCH_REPO:-p3terparker/watch-app}"
BUNDLE_ID="com.jacob.watch"
STATE_DIR="$HOME/Library/Application Support/Watch Updater"
STATE="$STATE_DIR/installed"
LABEL="com.jacob.watch-updater"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
channel="current-build"; dry=0; force=0; agent=""
for arg in "$@"; do
    case "$arg" in
        --stable)  channel="latest" ;;
        --dry-run) dry=1 ;;
        --force)   force=1 ;;
        --uninstall-agent) agent="$arg" ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "watch-update: unknown option $arg (try --help)" >&2; exit 2 ;;
    esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'watch-update: %s\n' "$*" >&2; exit 1; }

# --- clean-up of the background checker an earlier version could install (no longer offered)
if [ "$agent" = "--uninstall-agent" ]; then
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    rm -f "$PLIST"
    say "Background updates are off. (watch-update still works by hand.)"
    exit 0
fi

if [ "$channel" = "latest" ]; then api="https://api.github.com/repos/$REPO/releases/latest"
else api="https://api.github.com/repos/$REPO/releases/tags/$channel"; fi

work="$(mktemp -d "${TMPDIR:-/tmp}/watch-update.XXXXXX")"
mount_point=""
cleanup() {
    if [ -n "$mount_point" ]; then hdiutil detach "$mount_point" -quiet -force >/dev/null 2>&1 || true; fi
    rm -rf "$work"
}
trap cleanup EXIT

# --- what is the newest build? (the release is recreated on every passing build, so its publish time says which one it is)
curl -fsSL -H 'Accept: application/vnd.github+json' "$api" -o "$work/release.json" \
    || die "couldn't read $api — are you online, and has a build passed? (no '$channel' release yet means none has)"
field() { grep -o "\"$1\": *\"[^\"]*\"" "$work/release.json" | head -1 | sed 's/^[^:]*: *"//; s/"$//' || true; }
published="$(field published_at)"
title="$(field name)"
dmg_url="$(grep -o '"browser_download_url": *"[^"]*\.dmg"' "$work/release.json" | head -1 | sed 's/^[^:]*: *"//; s/"$//' || true)"
[ -n "$dmg_url" ] || die "that release has no .dmg attached"
[ -n "$published" ] || published="unknown"
# The checksum the build workflow prints in the notes (escaped newlines in the JSON), when there is one.
want_sha="$(grep -o '"body": *"[^"]*\(\\"[^"]*\)*"' "$work/release.json" | grep -o '[0-9a-f]\{64\}' | head -1 || true)"

# --- where is Watch, and what is installed?
dest="${WATCH_DEST:-}"
if [ -z "$dest" ]; then
    if [ -d "/Applications/Watch.app" ]; then dest="/Applications/Watch.app"
    elif [ -d "$HOME/Applications/Watch.app" ]; then dest="$HOME/Applications/Watch.app"
    else dest="$HOME/Applications/Watch.app"; fi
fi
installed=""; [ -f "$STATE" ] && installed="$(cat "$STATE")"
current_version="not installed"
if [ -d "$dest" ]; then
    current_version="$(defaults read "$dest/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?') ($(defaults read "$dest/Contents/Info" CFBundleVersion 2>/dev/null || echo '?'))"
fi

say "Newest:    ${title:-$channel} — published $published"
say "Installed: $current_version at $dest"
if [ "$installed" = "$published" ] && [ -d "$dest" ] && [ "$force" = 0 ]; then
    say "Already up to date."
    exit 0
fi
if [ "$dry" = 1 ]; then
    say "Would download $dmg_url"
    say "Would check SHA-256 ${want_sha:-(none listed in the release notes)}"
    say "Would quit Watch if it is running, replace $dest and open it again."
    exit 0
fi

# --- download (curl: not quarantined) and check it
say "Downloading…"
dmg="$work/Watch.dmg"
curl -fL --progress-bar "$dmg_url" -o "$dmg" || die "download failed"
if [ -n "$want_sha" ]; then
    got="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
    [ "$got" = "$want_sha" ] || die "checksum mismatch (got $got, release says $want_sha) — not installing"
    say "Checksum OK."
else
    say "No checksum in the release notes; skipping that check."
fi

mount_point="$work/mount"; mkdir -p "$mount_point"
hdiutil attach "$dmg" -nobrowse -readonly -quiet -mountpoint "$mount_point" || die "couldn't open the disk image"
src="$mount_point/Watch.app"
[ -d "$src" ] || die "no Watch.app inside the disk image"

# --- quit Watch (if it is running), swap, relaunch
if pgrep -x Watch >/dev/null 2>&1; then
    say "Quitting Watch…"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do pgrep -x Watch >/dev/null 2>&1 || break; sleep 0.25; done
    pgrep -x Watch >/dev/null 2>&1 && die "Watch didn't quit — close it and run this again"
fi

mkdir -p "$(dirname "$dest")"
staged="$dest.updating"
rm -rf "$staged"
ditto "$src" "$staged" || die "couldn't copy the new Watch next to $dest"
xattr -cr "$staged" 2>/dev/null || true             # belt and braces: no quarantine mark, whatever fetched it
if [ -d "$dest" ]; then
    rm -rf "$dest" || { rm -rf "$staged"; die "couldn't replace $dest (try WATCH_DEST=\"$HOME/Applications/Watch.app\")"; }
fi
mv "$staged" "$dest"
mkdir -p "$STATE_DIR"; printf '%s' "$published" > "$STATE"

new_version="$(defaults read "$dest/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?') ($(defaults read "$dest/Contents/Info" CFBundleVersion 2>/dev/null || echo '?'))"
say "Installed $new_version. Opening Watch…"
open "$dest"

