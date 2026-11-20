# Testing RiffShelf

RiffShelf has four kinds of tests. The first three run automatically; the last is a manual pass on real devices before a release or demo.

| Kind | Location | Runs on | In CI |
|---|---|---|---|
| Unit and widget tests | `test/` | Your computer | Every push |
| Backend tests | `server/tests/` | Your computer | Every push |
| On-device integration tests | `integration_test/` | Emulator, simulator, or phone | Android on every push; iOS on manual runs |
| Manual regression pass | [regression-checklist.md](regression-checklist.md) | Physical Android and iOS devices | No |

## Unit and widget tests

```sh
flutter test
flutter test test/tuner_test.dart        # one file
flutter test --name "duplicate key"      # tests whose name matches
```

These tests never use the network or a real microphone:

- Databases use `sqflite_common_ffi`, either in memory or in a temp folder.
- The tuner uses `FakeInput` from `test/tuner_test.dart` to feed generated sine waves.
- Songsterr responses come from `test/support/songsterr_fixtures.dart`.
- Guitar Pro files come from `test/fixtures/`.

When you fix a bug, add a test here that fails without the fix.

## Backend tests

From `server/`, with the virtual environment from [server/README.md](../server/README.md) active:

```sh
python -m pytest -q
```

All provider calls are mocked.

## On-device integration tests

| File | What it checks | Network |
|---|---|---|
| `app_smoke_test.dart` | App launches, every tab shows its main control, practice history opens and closes, theme switch is saved | None |
| `storage_on_device_test.dart` | Text import plus save, search, duplicate detection, delete, and reopen against the platform's native SQLite | None |
| `live_songsterr_search_test.dart` | Direct Songsterr search | Live, manual only |
| `live_backend_search_test.dart` | Discover through a running backend | Live, manual only |

Start an emulator or simulator, find its id with `flutter devices`, then run:

```sh
flutter test integration_test/app_smoke_test.dart -d <device-id>
flutter test integration_test/storage_on_device_test.dart -d <device-id>
```

The storage test uses its own temporary database file and deletes it afterward, so it does not change your library. The smoke test reads the real on-device library and restores the theme setting when it finishes.

The live tests need internet access and are not run in CI. See [online-search.md](online-search.md) for how to run the backend test.

## Continuous integration

`.github/workflows/ci.yml` runs on every push and pull request:

- **backend:** Python syntax check, Ruff, and pytest.
- **validate:** `dart format`, `flutter analyze`, `flutter test`, and a debug APK build.
- **android-emulator:** boots an Android emulator and runs the offline integration tests.
- **ios-simulator:** builds the iOS simulator app and runs the offline integration tests on a booted simulator. This job only runs when started manually from the Actions tab (**Run workflow**), because macOS runners are slower and limited.

## Before a demo or release

1. Make sure CI is green on the commit you are building, and run the iOS simulator job manually.
2. Build the Android APK and iOS app (see [handoff.md](handoff.md#building-release-artifacts)).
3. Work through [regression-checklist.md](regression-checklist.md) on at least one Android phone and one iPhone.
4. File an issue for each failure and link it to the release milestone.
