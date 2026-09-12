# TravelEase mobile

## Required toolchain

All Android builds use the versions checked into this repository:

- Flutter 3.47.1 (Dart 3.13.1), defined in `.fvmrc`
- JDK 17
- Gradle 8.14, Android Gradle Plugin 8.11.1, and Kotlin 2.2.20, supplied by the checked-in Android project

Install [FVM](https://fvm.app/) once, then run these commands from `mobile`:

```powershell
dart pub global activate fvm
fvm install
fvm flutter pub get
fvm flutter build apk --debug
```

Use `fvm flutter` for every Flutter command in this project. Do not use a globally installed Flutter SDK to build it.

## Dependency policy

`pubspec.lock` is committed and is part of the build configuration. Use `fvm flutter pub get` after pulling changes; do not run `pub upgrade` unless deliberately updating dependencies and committing both `pubspec.yaml` and `pubspec.lock`.

The app previously pinned `video_player` 2.8.2, which selected `video_player_android` 2.4.17. That Android plugin still referenced Flutter's removed `PluginRegistry.Registrar` API, so builds failed on newer Flutter SDKs. The tested `video_player` 2.14.0 resolution selects `video_player_android` 2.12.2 instead.

CI runs the same Flutter and Java versions for every pull request.
