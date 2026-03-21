#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POS_DIR="$SCRIPT_DIR/../apps/pos"

MODE="${1:-debug}"   # debug | release
TARGET="${2:-apk}"  # apk | aab | both

usage() {
  echo "Usage: $0 [debug|release] [apk|aab|both]"
  echo "  Default: debug apk"
  exit 1
}

[[ "$MODE" =~ ^(debug|release)$ ]] || usage
[[ "$TARGET" =~ ^(apk|aab|both)$ ]] || usage

echo "==> Building GastroCore POS — mode=$MODE target=$TARGET"
cd "$POS_DIR"
flutter pub get

build_apk() {
  echo "==> Building APK ($MODE)..."
  flutter build apk "--$MODE"
  if [[ "$MODE" == "release" ]]; then
    echo "==> APK: build/app/outputs/flutter-apk/app-release.apk"
  else
    echo "==> APK: build/app/outputs/flutter-apk/app-debug.apk"
  fi
}

build_aab() {
  echo "==> Building AAB ($MODE)..."
  flutter build appbundle "--$MODE"
  if [[ "$MODE" == "release" ]]; then
    echo "==> AAB: build/app/outputs/bundle/release/app-release.aab"
  else
    echo "==> AAB: build/app/outputs/bundle/debug/app-debug.aab"
  fi
}

case "$TARGET" in
  apk)  build_apk ;;
  aab)  build_aab ;;
  both) build_apk; build_aab ;;
esac

echo "==> Build complete."
