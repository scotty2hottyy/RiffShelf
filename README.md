# RiffShelf

RiffShelf is a Flutter application for discovering, organizing, and practicing guitar and bass tablature on Android and iOS. Its navigation includes Discover, Practice, Tuner, Library, and Settings.

The bottom navigation keeps screens mounted while switching tabs and restores the selected tab when the app is restored. Screen functionality will be added in later milestones.

The app uses a dark, near-black theme with teal accents and outlined surfaces, inspired by the tab-practice visual reference.

## Project structure

- `lib/main.dart` starts the app; `lib/app.dart` configures the app theme and root.
- `lib/navigation/` contains the persistent bottom-navigation shell.
- `lib/screens/` contains the individual tab screens.
- `lib/widgets/` contains UI shared across screens.
- Add `lib/services/` or `lib/models/` when those layers are introduced by later features.

## Requirements

- Flutter SDK with Dart 3.13.4 or later
- Android Studio or Android SDK, with an Android emulator configured
- macOS with Xcode and its command-line tools for iOS; an iOS Simulator or an Apple device

Run `flutter doctor` and resolve platform-specific requirements before building. For a physical iOS device, configure your own signing team in `ios/Runner.xcworkspace` in Xcode.

## Setup and run

```sh
git clone https://github.com/scotty2hottyy/RiffShelf.git
cd RiffShelf
flutter pub get
flutter devices
```

Start an Android emulator using Android Studio, then run `flutter run -d <device-id>`. To build a debug APK, run `flutter build apk --debug`.

On macOS, start an iOS Simulator with `open -a Simulator`, then run `flutter run -d <device-id>`. For a connected iOS device, select its ID instead and configure signing in Xcode. To build for the simulator, run `flutter build ios --simulator --debug`.

## Checks

```sh
flutter analyze
flutter test
```

## Practice timing compatibility

Timed practice uses structured measure and note data from supported guitar and bass arrangements, including imported GP3, GP4, GP5, and GPX tracks. It supports four, five, six, and other positive string counts, alternate tunings, simultaneous notes, rests, sustained note durations, variable time signatures, speed changes, seeking, and measure-section loops. Notes scroll from right to left. The authored BPM sets the normal speed; tabs without BPM use a 100 BPM practice reference.

In Practice, choose **Note by note** and press **Play** to wait for each correct pitch. This mode requires known pitches, but can use approximate timing for note order. Ordinary scrolling uses authored timing when valid and offers labeled approximate timing for readable ASCII tabs or structured tabs with unreliable timing. Approximate scrolling spaces source beat groups or ASCII fret columns evenly; it does not infer the song’s rhythm. Tabs without readable fret notes remain view-only. Tempo automation, repeats, ties, and expressive techniques from source files are not currently modeled by the practice timeline.

## Search and metadata backend

The independent FastAPI service and its setup, testing, and deployment-planning instructions are in [server/README.md](server/README.md).

## Album artwork

Album lookup and cover downloads connect directly to MusicBrainz and Cover Art Archive; no backend configuration or API key is required. New saved tabs with unambiguous high-confidence matches are checked in the background. You can choose, change, or remove a release on the saved-tab detail screen. Covers are cached locally for offline viewing, with an abstract fallback when artwork is unavailable. See [online search and artwork](docs/online-search.md) for matching and rate-limit details.
