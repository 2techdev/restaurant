#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POS_DIR="$SCRIPT_DIR/../apps/pos"
COVERAGE_DIR="$POS_DIR/coverage"

echo "==> Running Flutter tests with coverage..."
cd "$POS_DIR"
flutter pub get
flutter test --coverage

echo ""
echo "==> Coverage report written to: $COVERAGE_DIR/lcov.info"

# Generate HTML report if lcov is available
if command -v genhtml &>/dev/null; then
  genhtml "$COVERAGE_DIR/lcov.info" \
    --output-directory "$COVERAGE_DIR/html" \
    --title "GastroCore POS Coverage" \
    --quiet
  echo "==> HTML coverage report: $COVERAGE_DIR/html/index.html"
else
  echo "==> Install lcov to generate HTML reports: sudo apt-get install lcov"
fi

echo "==> Tests complete."
