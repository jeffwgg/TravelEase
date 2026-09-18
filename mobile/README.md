# TravelEase mobile

## Required toolchain

All Android builds use the versions checked into this repository:

- Flutter 3.47.1 (Dart 3.13.1), defined in `.fvmrc`
- JDK 17
- Gradle 9.1.0, Android Gradle Plugin 9.0.1, and Kotlin 2.3.20, supplied by the checked-in Android project

Install [FVM](https://fvm.app/) once, then run these commands from `mobile`:

```powershell
dart pub global activate fvm
fvm install
fvm flutter pub get
fvm flutter build apk --debug
```

Use `fvm flutter` for Flutter commands, or use the Windows wrapper described below when SDK paths contain spaces. Do not use a globally installed Flutter SDK to build it.

### Windows: SDK version mismatch

If `flutter pub get` reports Dart 3.11.5 but requires `>=3.13.1`, your terminal is using an older global Flutter installation. Keep the SDK constraints and lockfile; install and use the version in `.fvmrc` instead.

If PowerShell cannot find `fvm` after installation, these commands work without changing PATH. Run them from `mobile`:

```powershell
dart pub global run fvm:main install
dart pub global run fvm:main flutter --version
dart pub global run fvm:main flutter pub get
```

To enable the shorter `fvm` command for the current PowerShell session (with the default Pub cache location):

```powershell
$env:Path += ";$env:LOCALAPPDATA\Pub\Cache\bin"
```

For VS Code opened at the repository root, set `dart.flutterSdkPath` to `mobile/.fvm/flutter_sdk` in workspace settings after installation. If only `mobile` is open, use `.fvm/flutter_sdk`. Reload VS Code so the Dart extension uses the project SDK.

## Dependency policy

`pubspec.lock` is committed and is part of the build configuration. Use `fvm flutter pub get` after pulling changes; do not run `pub upgrade` unless deliberately updating dependencies and committing both `pubspec.yaml` and `pubspec.lock`.

The app previously pinned `video_player` 2.8.2, which selected `video_player_android` 2.4.17. That Android plugin still referenced Flutter's removed `PluginRegistry.Registrar` API, so builds failed on newer Flutter SDKs. The tested `video_player` 2.14.0 resolution selects `video_player_android` 2.12.2 instead.

CI runs the same Flutter and Java versions for every pull request.


### Windows SDK paths with spaces

On Windows, use .\flutterw.cmd instead of fvm flutter if the SDK path contains spaces.
From mobile, run .\flutterw.cmd build apk --debug or .\flutterw.cmd run.
The wrapper invokes the pinned FVM SDK using Windows short names.
If short names are unavailable, install the pinned SDK in a path without spaces.

For IDE builds, dart.flutterSdkPath must also point to a space-free absolute SDK
path instead of the relative path above. Configure this in local VS Code settings
and reload VS Code after changing the setting.
