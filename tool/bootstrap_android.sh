#!/usr/bin/env bash
set -euo pipefail
if [ ! -d android ]; then
  flutter create . --platforms=android --project-name=level_me --org=com.mackywild --no-pub
fi
if [ -f android/app/src/main/AndroidManifest.xml ]; then
  sed -i 's/android:label="level_me"/android:label="LEVEL ME"/' android/app/src/main/AndroidManifest.xml
fi
