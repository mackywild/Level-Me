# LEVEL ME ⚔️

**Real-life RPG for Android** built with Flutter.

Your actions become EXP. Complete one-time/daily/weekly quests, grow six personal attributes, attack bosses with quest clears, and unlock the achievement collection.

## Android APK via GitHub Actions
The `Build Android APK` workflow installs Flutter on GitHub's runner, generates the Android project, runs `flutter analyze` and `flutter test`, and builds an APK artifact. Android Studio is not needed on your computer.

Download `level-me-test-apk` for testing only. For persistent installation use the manually triggered `level-me-signed-release-apk` after configuring [fixed Android release signing](docs/ANDROID_RELEASE_SIGNING.md).

Do not uninstall an existing app to resolve signature mismatch without a verified backup. Production signing requires owner setup; Play Store readiness is not claimed.

See [game design](docs/GAME_DESIGN.md).
