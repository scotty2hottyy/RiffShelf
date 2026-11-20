# Contributing to RiffShelf

This guide covers the day-to-day workflow for changing RiffShelf. Read the [README](README.md) for setup and [docs/architecture.md](docs/architecture.md) for how the code is organized.

## Workflow

1. Pick an issue from the project board and move it to **In progress**.
2. Create a branch from `main` named after the issue, for example `31-developer-docs` or `fix/tuner-crash`.
3. Make focused commits. Each commit should build and describe one change in the imperative mood ("Add tuner preset picker", not "added stuff").
4. Run the checks below before pushing.
5. Open a pull request that links the issue (`Closes #31`) and describes how you tested the change. Include screenshots for UI changes.
6. Move the card to **Done** after the pull request is merged.

## Checks

Run these from the repository root before every push. CI runs the same commands.

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

If you changed `server/`, also run from that folder:

```sh
python -m compileall -q app tests
python -m ruff check app tests
python -m pytest -q
```

To fix formatting automatically, run `dart format .`.

## Code conventions

- Put new code in the existing layers: domain types and repositories in `lib/core/`, feature logic in `lib/features/<feature>/`, top-level tabs in `lib/screens/`, shared UI in `lib/widgets/`.
- Reuse existing repositories, providers, and models instead of creating parallel versions.
- Depend on interfaces (`TabRepository`, `TabSourceProvider`, `TunerAudioInput`) so code can be tested with fakes.
- Treat imported files and network responses as untrusted. Validate them at the boundary and surface errors to the user instead of hiding them.
- Use parameterized SQL. When changing the database schema, bump the version in `SqliteTabRepository` and add an `onUpgrade` step.
- Add `///` doc comments to public classes and methods whose purpose is not obvious from the name.
- Do not add dependencies unless the change needs them, and explain why in the pull request.

## Tests

- Add or update a test for every behavior change. Unit and widget tests go in `test/`, mirroring the `lib/` file they cover.
- Tests must not need the network or a real microphone. Use the fixtures in `test/fixtures/` and `test/support/`, and the fakes used by existing tests.
- On-device tests go in `integration_test/`. Mark tests that need live services clearly and keep them out of CI.

See [docs/testing.md](docs/testing.md) for details.

## Pull request checklist

- [ ] Linked to an issue
- [ ] `dart format`, `flutter analyze`, and `flutter test` pass
- [ ] Tests added or updated
- [ ] Docs updated if setup or behavior changed
- [ ] Screenshots attached for UI changes
- [ ] Checked on Android or iOS if the change affects device features (microphone, file picker, storage)
