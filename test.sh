#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/glasskit-watch-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 "$HERE/Sources/Downloads.swift" "$HERE/Sources/PlaybackPositions.swift" \
  "$HERE/Sources/Links.swift" "$HERE/Sources/SearchSupport.swift" "$HERE/Sources/Tiling.swift" "$HERE/Sources/PlayerZones.swift" "$HERE/Sources/Library.swift" "$HERE/Sources/MediaTools.swift" "$HERE/Sources/NowPlaying.swift" "$HERE/Sources/ArtworkStyle.swift" "$HERE/Sources/StreamSupport.swift" "$HERE/Sources/Queue.swift" "$HERE/Sources/Handoff.swift" "$HERE/Sources/Podcasts.swift" "$HERE/Tests/MediaToolsChecks.swift" "$HERE/Tests/QueueChecks.swift" "$HERE/Tests/PodcastChecks.swift" "$HERE/Tests/NowPlayingChecks.swift" "$HERE/Tests/StreamChecks.swift" "$HERE/Tests/main.swift" -o "$WORK/watch-tests"
"$WORK/watch-tests"
