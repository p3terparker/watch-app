# Contributing

Bug reports and pull requests are welcome. For anything bigger than a small fix, open an issue first so we can talk it through.

Start with the [README](README.md) for building and [MAP.md](MAP.md) for where things live.

## Before you send a PR

- Run `./check.sh`. If you changed the UI, also run `python3 Tests/panel.py` in a macOS GUI session.
- If you touched the bundled tools or packaging, run `python3 Tests/bundled.py build/universal/Watch.app/Contents/Helpers`, then `./package.sh` and `python3 scripts/verify_watch_package.py --canonical`.
- Tests use temporary preferences and fixture files. Keep it that way: no personal cookies or libraries, and close your regular copy of Watch before running the panel tests.
- Leave the bundle ID (`com.jacob.watch`), the preference keys, the hotkey and the `glasskit-watch://` scheme alone. Existing installs depend on them.
- Don't commit helper binaries, DMGs, caches, cookies or credentials.
- If you change what the app does, update `docs/FEATURES.md`. If you hit something odd, add it to `GOTCHAS.md`.

## Signing

Local builds are signed ad hoc. That's enough to run them on your own Mac but doesn't remove the Gatekeeper prompt for anyone else.

## License

Your contributions are under the same [MIT license](LICENSE) as the rest of Watch's code. Bundled tools keep their own licenses, so don't strip their notices (see [THIRD_PARTY.md](THIRD_PARTY.md)).
