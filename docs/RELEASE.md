# Releasing

## Building an installer

```sh
./package.sh
python3 scripts/verify_watch_package.py --canonical
```

That gives you `dist/Watch-<version>.dmg`, plus a `.sha256` file and a `-verification.json` report next to it. Packaging the same version again overwrites them, so bump the version if you want to keep the old one.

The app has to contain all four pinned tools (yt-dlp, FFmpeg, ffprobe, Deno) and the third-party notices and sources. If you're changing a pin, read [THIRD_PARTY.md](../THIRD_PARTY.md) first, then rebuild and run `Tests/bundled.py` from a clean temporary home. Never swap a binary inside an app that's already signed; rebuild the app.

## Versions on GitHub

The Releases page has two kinds of entry:

- **The stable release** is the newest `vX.Y` and is marked Latest. It's what the README's download link points at.
- **Current build** is a single pre-release, tag `current-build`, holding the newest build that passed the tests. Each passing push to a `claude/*` branch replaces it. Put `[no preview]` in a commit message to build and test without replacing it. If `docs/releases/next.md` exists, its text is shown on the pre-release as what's new.

The version number only goes up when a new batch of changes starts, not on every commit. Every push in the same batch keeps its number and just replaces the current build.

## Making a stable release

1. Write the release notes in `docs/releases/v<version>.md`, covering everything since the last stable release. Merge them to `main`.
2. Make sure the build you want has passed and is the current build.
3. Run the **Promote to stable** workflow from the Actions tab. Leave the tag as `current-build`. Tick *dry run* first if you want to see what it will do.

The workflow takes the installer already attached to the current build (it doesn't rebuild), checks its SHA-256, publishes `v<version>` as the latest release with your notes and the hash, and then deletes the current build and any old `vX.Y-preview` releases. If `docs/releases/next.md` exists, delete it in the same change so the next current build starts clean.

## Signing

Builds are signed ad hoc and not notarized, and nothing here sets up notarization. The first-run notes tell people how to get past Gatekeeper. `./check.sh --release` only checks that a built bundle meets the bar for a signed and notarized release (Developer ID, hardened runtime); it doesn't sign anything.

Don't claim support for something that hasn't been run: a clean Mac, the oldest macOS, real Intel hardware. Record what's been tried and what hasn't in [AUDIT.md](AUDIT.md).
