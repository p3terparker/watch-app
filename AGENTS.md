# Working on Watch App

- Read README.md, MAP.md, UX_SPEC.md and docs/AUDIT.md before changing behavior.
- This is a standalone repository. Never add dependencies on a sibling checkout or absolute developer paths.
- Preserve uncommitted work. Use scripts/build.sh, scripts/check.sh and scripts/package.sh; installation requires an explicit request.
- Keep the bundle ID, stored preference keys, hotkey and legacy URL handler stable unless a migration is designed and verified.
- Compile all top-level Sources/*.swift. Metadata/frameworks belong in Info.plist and scripts/app.json.
- Never test against production cookies or personal libraries, or launch a second production app instance. Use isolated fixtures.
- Keep helpers fully bundled and pinned. Do not add system-tool fallback or modify signed helpers at runtime.
- Update MAP.md, docs/FEATURES.md, version metadata, and docs/AUDIT.md for behavior changes. Add GOTCHAS entries for non-obvious fixes.
- Preserve third-party notices and sources when changing dependencies. The MIT license covers Watch's own code only.
- Building on one Mac does not prove support for every macOS version or real Intel hardware. Report remaining gaps accurately.
