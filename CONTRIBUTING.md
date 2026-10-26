# Contributing to Watch

Read README.md and AGENTS.md first. Keep changes focused and use temporary fixtures for downloads, libraries and asynchronous failures. Never commit credentials, browser cookies, user preferences, helper binaries, generated installers or local caches.

Run `./check.sh` for code changes. For UI changes, also run `python3 Tests/panel.py` in a macOS GUI session. For dependency/packaging changes, run the bundled integration fixture, `./package.sh`, and `python3 scripts/verify_watch_package.py --canonical`. Document tested behavior and remaining limitations in docs/AUDIT.md.

App behavior and helper versions are separate from Apple notarization. Local ad-hoc signing supports development; it does not remove recipient Gatekeeper prompts.

Changes to Watch's own code are contributed under the repository's MIT license. Preserve the licenses and notices of third-party components.
