#!/usr/bin/env bash
# Builds the 3D Chess APK and Android App Bundle (AAB) from this source tree.
# Needs: Flutter (stable, Dart >= 3.3), JDK 17, Android SDK (platform 35 + NDK, installed automatically by Gradle),
# internet access to pub.dev, Google Maven and Maven Central. Run from anywhere:
#
#   tools/build.sh                 # analyze + tests + release APK + AAB -> dist/
#   SKIP_TESTS=1 tools/build.sh    # skip flutter test
#   DEBUG_APK=1  tools/build.sh    # also build a debug APK
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="com.carlos.chess3d"
PKG_DIR="${PKG//./\/}"
FILAMENT_VERSION="${FILAMENT_VERSION:-1.72.0}"
OUT="$ROOT/dist"

cd "$ROOT"
echo "== flutter"
flutter --version

echo "== generate Android platform project (once)"
if [ ! -d android ]; then
  flutter create --platforms android --org com.carlos --project-name chess3d --no-pub .
fi

APP=android/app
SRC="$APP/src/main"

echo "== apply overlay (Filament renderer, manifest, icons)"
rm -f "$APP/build.gradle" "$APP/build.gradle.kts"
sed -e "s/__PKG__/$PKG/g" -e "s/__FILAMENT__/$FILAMENT_VERSION/g" android_overlay/app_build.gradle.kts > "$APP/build.gradle.kts"
rm -rf "$SRC/kotlin" "$SRC/java"
mkdir -p "$SRC/kotlin/$PKG_DIR"
for f in android_overlay/kotlin/*.kt; do
  sed "s/__PKG__/$PKG/g" "$f" > "$SRC/kotlin/$PKG_DIR/$(basename "$f")"
done
cp -r android_overlay/res/. "$SRC/res/"
cp android_overlay/AndroidManifest.xml "$SRC/AndroidManifest.xml"

echo "== vendor the Stockfish plugin (patched for Gradle 9 / AGP 9)"
STOCKFISH_VERSION=1.8.1
if [ ! -d packages/stockfish ]; then
  flutter pub cache add stockfish --version "$STOCKFISH_VERSION"
  SRC_DIR="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/stockfish-$STOCKFISH_VERSION"
  [ -d "$SRC_DIR" ] || { echo "stockfish plugin not found in pub cache: $SRC_DIR"; exit 1; }
  mkdir -p packages
  cp -r "$SRC_DIR" packages/stockfish
  rm -rf packages/stockfish/example   # not needed; ios/Stockfish/src IS needed (the Android CMake build compiles it)
fi
cp android_overlay/stockfish_build.gradle packages/stockfish/android/build.gradle

echo "== dependencies + static analysis"
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings

if [ -z "${SKIP_TESTS:-}" ]; then
  echo "== Dart tests"
  flutter test --reporter expanded
fi

echo "== build APK"
mkdir -p "$OUT"
flutter build apk --release --target-platform android-arm64
cp build/app/outputs/flutter-apk/app-release.apk "$OUT/chess3d-release.apk"

echo "== build AAB"
flutter build appbundle --release --target-platform android-arm64
cp build/app/outputs/bundle/release/app-release.aab "$OUT/chess3d-release.aab"
if [ -n "${DEBUG_APK:-}" ]; then
  flutter build apk --debug --target-platform android-arm64
  cp build/app/outputs/flutter-apk/app-debug.apk "$OUT/chess3d-debug.apk"
fi

echo "== verify"
for a in "$OUT"/*.apk "$OUT"/*.aab; do
  [ -s "$a" ] || { echo "EMPTY: $a"; exit 1; }
  echo "$(basename "$a"): $(stat -c %s "$a") bytes"
done
echo "Done. APK and AAB in $OUT"
