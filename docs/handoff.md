# Team handoff

This is the starting point for anyone taking over RiffShelf. It covers where the project stands, what is left, and what to watch out for.

## Start here

1. Follow [Setup and run](../README.md#setup-and-run) in the README and confirm `flutter test` passes.
2. Read [architecture.md](architecture.md) to see how the code is organized.
3. Read [CONTRIBUTING.md](../CONTRIBUTING.md) for the branch and pull request workflow.
4. Read [testing.md](testing.md) before changing practice, tuner, or import code.

## What works

| Area | Status |
|---|---|
| Discover | Search Songsterr directly or through the optional backend, pick a track, and save it. |
| Library | Import GP3/GP4/GP5/GPX and text tabs, filter, tag, favorite, edit, and delete. Album artwork from MusicBrainz and Cover Art Archive, cached offline. |
| Practice | Structured tab viewer, scrolling playback with tempo control, section loops, note-by-note mode using the microphone, and saved practice history. |
| Tuner | Chromatic tuner with guitar, bass, and custom tunings. |
| Settings | Light/dark theme and album-type filtering for artwork. |
| Backend | FastAPI search and MusicBrainz metadata endpoints with mocked tests. Not deployed. |

## Known limitations

- **Songsterr endpoints are unofficial.** They can change without notice. Errors are shown to the user, but search and downloads will break if the API changes. Check `lib/features/search/data/` first if search stops working.
- **The backend is not deployed.** Builds without `RIFFSHELF_API_BASE_URL` search Songsterr directly. See [online-search.md](online-search.md).
- **Practice timing does not model** tempo automation, repeats, ties, or expressive techniques from source files.
- **Note-by-note mode does not measure rhythm.** It waits for each correct pitch and does not score missed notes.
- **Practice history is device-only.** There is no account or sync.
- **Artwork licensing is unknown.** Cover Art Archive does not provide licenses for covers; review this before any public release.
- **Issues #14 and #15** stay open until search through a deployed HTTPS backend is verified on a physical device.

## Remaining work

These items are on the project board at the time of writing:

- **Milestone 6:** end-to-end and regression testing on Android and iOS (#29), emulator and simulator CI (#30), developer documentation (#31), final demo builds (#32), and fixes from final testing (#43).
- **Stretch goals:** microphone-controlled note advancement (#33), piano/keyboard support (#34), and accuracy tracking over time (#35).

## Building release artifacts

```sh
flutter build apk --release
flutter build ios --release
```

Add `--dart-define=RIFFSHELF_API_BASE_URL=https://...` to either command to use a deployed backend. iOS release builds need a signing team set in `ios/Runner.xcworkspace`.

## Where things are

| Need to change... | Look in |
|---|---|
| A top-level screen | `lib/screens/` |
| Search or download behavior | `lib/features/search/` |
| File import | `lib/features/import/` |
| Practice playback or note matching | `lib/features/tabs/` |
| Tuner accuracy or tunings | `lib/features/tuner/`, `lib/core/models/tuning.dart` |
| Database schema | `lib/core/database/sqlite_tab_repository.dart` (bump the version and add an `onUpgrade` step) |
| Theme colors | `lib/core/theme_provider.dart` |
| CI | `.github/workflows/ci.yml` |
| Backend | `server/` |
