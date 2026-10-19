#!/usr/bin/env bash
set -euo pipefail
if [ ! -d android ]; then
  flutter create . --platforms=android --project-name=level_me --org=com.mackywild --no-pub
fi
# flutter create adds a sample test referencing MyApp; this app uses LevelMeApp.
# Keep our own tests and remove only the generated sample.
if [ -f test/widget_test.dart ] && grep -q 'MyApp' test/widget_test.dart; then
  rm test/widget_test.dart
fi
if [ -f android/app/src/main/AndroidManifest.xml ]; then
  sed -i 's/android:label="level_me"/android:label="LEVEL ME"/' android/app/src/main/AndroidManifest.xml
fi
