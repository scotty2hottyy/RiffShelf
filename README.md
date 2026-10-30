# RiffShelf

RiffShelf is a Flutter application for discovering, organizing, and practicing guitar and bass tablature on Android and iOS. Its initial navigation includes Discover, Practice, Tuner, Library, and Settings placeholder screens.

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
