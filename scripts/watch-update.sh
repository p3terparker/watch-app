#!/bin/bash
# watch-update — replace the Watch on this Mac with the newest build from GitHub, in one command.
#
#   watch-update              the newest passing build (the "Current build" pre-release)
#   watch-update --stable     the release marked Latest instead
#   watch-update --dry-run    say what it would do; change nothing
#   watch-update --force      reinstall even if this build is already installed
#   watch-update --install-agent    check every 10 minutes in the background and update by itself (a launchd agent)
#   watch-update --uninstall-agent  stop doing that
#   watch-update --auto       what the agent runs: quiet, logs to ~/Library/Application Support/Watch Updater/updater.log,
#                             shows a notification when it has updated Watch (which quits and reopens it)
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
LOG="$STATE_DIR/updater.log"
channel="current-build"; dry=0; force=0; auto=0; agent=""
for arg in "$@"; do
    case "$arg" in
        --stable)  channel="latest" ;;
        --dry-run) dry=1 ;;
        --force)   force=1 ;;
        --auto)    auto=1 ;;
        --install-agent|--uninstall-agent) agent="$arg" ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "watch-update: unknown option $arg (try --help)" >&2; exit 2 ;;
    esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'watch-update: %s\n' "$*" >&2; exit 1; }

# --- the background agent: this script, copied to a fixed place, run by launchd every 10 minutes and at login
if [ "$agent" = "--uninstall-agent" ]; then
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    rm -f "$PLIST"
    say "Background updates are off. (watch-update still works by hand.)"
    exit 0
fi
if [ "$agent" = "--install-agent" ]; then
    [ -f "$0" ] || die "run this from the downloaded file, not piped into bash"
    mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents"
    installed_script="$STATE_DIR/watch-update"
    [ "$0" -ef "$installed_script" ] || cp "$0" "$installed_script"
    chmod +x "$installed_script"
    cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$installed_script</string><string>--auto</string></array>
    <key>RunAtLoad</key><true/>
    <key>StartInterval</key><integer>600</integer>
    <key>ProcessType</key><string>Background</string>
</dict></plist>
PLISTEOF
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" || die "couldn't start the background agent"
    say "Done. Every 10 minutes (and now) it checks GitHub and, if there is a newer build, installs it."
    say "Updating quits and reopens Watch, with a notification. Log: $LOG"
    say "By hand any time: $installed_script   ·   turn off: $installed_script --uninstall-agent"
    exit 0
fi

# Background runs say nothing on screen: everything goes to the log (kept small), and only one runs at a time.
if [ "$auto" = 1 ]; then
    mkdir -p "$STATE_DIR"
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 200000 ]; then tail -c 50000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; fi
    exec >>"$LOG" 2>&1
    echo "--- $(date '+%Y-%m-%d %H:%M:%S')"
    mkdir "$STATE_DIR/lock" 2>/dev/null || {
        if [ -n "$(find "$STATE_DIR/lock" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then rmdir "$STATE_DIR/lock" 2>/dev/null || true; fi
        echo "another update is running"; exit 0
    }
fi

if [ "$channel" = "latest" ]; then api="https://api.github.com/repos/$REPO/releases/latest"
else api="https://api.github.com/repos/$REPO/releases/tags/$channel"; fi

work="$(mktemp -d "${TMPDIR:-/tmp}/watch-update.XXXXXX")"
mount_point=""
cleanup() {
    if [ -n "$mount_point" ]; then hdiutil detach "$mount_point" -quiet -force >/dev/null 2>&1 || true; fi
    rm -rf "$work"
}
trap 'cleanup; [ "$auto" = 1 ] && rmdir "$STATE_DIR/lock" 2>/dev/null; true' EXIT

# --- what is the newest build? (the release is recreated on every passing build, so its publish time says which one it is)
if ! curl -fsSL -H 'Accept: application/vnd.github+json' "$api" -o "$work/release.json"; then
    # Offline, rate-limited, or no build has passed yet: nothing to do. By hand that is worth saying; in the background it is normal.
    if [ "$auto" = 1 ]; then echo "couldn't read the release (offline, or none yet)"; exit 0; fi
    die "couldn't read $api — is the build finished? (no '$channel' release yet means no build has passed)"
fi
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
if [ "$auto" = 1 ]; then
    osascript -e "display notification \"Watch $new_version is installed and open.\" with title \"Watch updated\"" >/dev/null 2>&1 || true
fi
