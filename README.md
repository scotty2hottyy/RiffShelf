# RiffShelf

RiffShelf is a Flutter starter application for Android and iOS. It currently displays a welcome screen.

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
