# RiffShelf architecture

This document explains how the RiffShelf app is put together so a new developer can find their way around the code. For setup and run instructions, see the [README](../README.md). For the optional backend, see [server/README.md](../server/README.md).

## Overview

RiffShelf is a single Flutter app for Android and iOS. Everything a user needs works offline: saved tabs, practice history, the tuner, and settings live on the device. Network access is only used to search for tabs, download a selected arrangement, and look up album artwork.

```
┌──────────────────────────── Flutter app ────────────────────────────┐
│  lib/main.dart → RiffShelfApp → MainNavigation (bottom nav shell)   │
│                                                                     │
│   Discover   Library   Practice   Tuner   Settings   ← lib/screens  │
│      │          │         │         │        │                      │
│      ▼          ▼         ▼         ▼        ▼                      │
│   search/    library/   tabs/     tuner/   theme + artwork prefs    │
│   import/    artwork/                                ← lib/features │
│      │          │         │                                         │
│      └──────────┴────┬────┘                                         │
│                      ▼                                              │
│        core/models  +  core/database (SQLite)        ← lib/core     │
└─────────────────────────────────────────────────────────────────────┘
          │ HTTPS (optional)                │ HTTPS
          ▼                                 ▼
   server/ FastAPI search API      Songsterr, MusicBrainz,
   (RIFFSHELF_API_BASE_URL)        Cover Art Archive
```

## Startup and navigation

- `lib/main.dart` initializes Flutter bindings, loads the saved theme (`ThemeProvider.init`) and artwork preferences, then runs the app inside a `ChangeNotifierProvider<ThemeProvider>`.
- `lib/app.dart` builds `MaterialApp` with a restoration scope so the selected tab survives app restarts.
- `lib/navigation/main_navigation.dart` holds the bottom navigation bar. Screens live in an `IndexedStack`, so switching tabs keeps each screen's state mounted. The selected index is a `RestorableInt`.

## Layers

### `lib/core/`

Shared, UI-independent code.

- `models/` defines the domain types: `SavedTab` (a library item), `TabStructure` (measures, beats, notes), `Tuning`, `InstrumentType`, and `PracticeSession`.
- `database/` defines repository interfaces (`TabRepository`, `PracticeSessionRepository`) and their SQLite implementations. Both tables live in one `riffshelf.db` file. Schema changes go through the versioned `onUpgrade` in `SqliteTabRepository`; bump the version and add a migration step instead of editing `onCreate` alone.
- `theme_provider.dart` stores the light/dark preference in `SharedPreferences` and builds both `ThemeData` variants.

### `lib/features/`

Each folder groups one feature's logic and feature-specific widgets.

| Folder | Responsibility |
|---|---|
| `search/` | Online tab search, split into `domain/` (provider interfaces and result types), `data/` (Songsterr and backend clients), and `application/` (`TabSearchService`, which picks the provider and validates downloaded tabs). |
| `import/` | Importing local files. `TabImportService` detects the format; `GuitarProImporter` handles GP3/GP4/GP5/GPX and `AsciiTabParser` handles plain-text tabs. Imports are de-duplicated with a SHA-256 `importKey`. |
| `tabs/` | Viewing and practicing a tab: the structured viewer, `PracticeTimeline` (turns measures into timed note events), `NoteMatcher` and `PracticeProgressionController` (note-by-note mode), scoring, and practice history. |
| `tuner/` | Microphone capture (`TunerAudioInput`), `PitchDetector`, `TunerController`, and saved custom tunings. |
| `artwork/` | MusicBrainz and Cover Art Archive lookup, caching covers on disk, and the album picker. |
| `library/` | Editing saved-tab details. |

### `lib/screens/` and `lib/widgets/`

`screens/` holds the five top-level tabs. They compose feature code and should stay thin. `widgets/` holds small UI pieces shared across screens.

## Key flows

### Search and save a tab

1. Discover builds a `TabSearchService` with `SongsterrProvider`. If `RIFFSHELF_API_BASE_URL` was passed at build time, a `BackendTabSearchClient` handles the search step instead.
2. The user picks a result. If the song has several tracks, the provider throws `TabTrackSelectionException` with the options and the UI asks which track to use.
3. `TabSearchService.fetch` downloads the arrangement and rejects it if it has no playable notes.
4. The tab is saved through `TabRepository.save` and a background artwork lookup starts.

### Practice

1. `PracticeTimeline.forScrolling` converts the tab's measures into a sorted list of `TimedNoteEvent`s. It falls back to approximate, evenly spaced timing when the source timing is unreliable.
2. In scrolling mode the screen advances by tempo. In note-by-note mode, `PracticeProgressionController` waits for `NoteMatcher` to confirm each expected pitch from the tuner's `PitchDetector`.
3. Saving a session writes a `PracticeSession` row through `PracticeSessionRepository`.

### Tuner

`TunerController` reads 16-bit PCM from a `TunerAudioInput`, runs `PitchDetector` on a sliding window, and maps the result to the nearest string in the selected `TuningPreset`. The audio input is an interface, so tests use a fake microphone.

## External services

| Service | Used for | Notes |
|---|---|---|
| Songsterr | Search, track lists, tab downloads | Unofficial endpoints that can change. Errors are shown to the user. |
| RiffShelf backend (`server/`) | Optional search proxy | Enabled with `--dart-define=RIFFSHELF_API_BASE_URL=...`. Must be HTTPS in release builds. |
| MusicBrainz / Cover Art Archive | Album artwork | Rate-limited to one request per second. Failures never block saving tabs. |

See [online-search.md](online-search.md) for details on matching rules and rate limits.

## Testing

Unit and widget tests live in `test/` and run with `flutter test`. They use `sqflite_common_ffi` for an in-memory database and fakes for the microphone and network. On-device tests live in `integration_test/`. See [testing.md](testing.md) for the full guide.
