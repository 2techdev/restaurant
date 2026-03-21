#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POS_DIR="$SCRIPT_DIR/../apps/pos"

echo "==> Running Flutter analyze..."
cd "$POS_DIR"
flutter pub get
flutter analyze --no-fatal-infos
echo "==> Analysis complete."
