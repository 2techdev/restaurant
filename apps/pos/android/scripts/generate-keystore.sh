#!/usr/bin/env bash
# Generate the GastroCore Android release keystore.
#
# Run once per release-signing identity. The resulting .jks file must
# be stored securely (Vault / 1Password) — losing it permanently
# breaks Play Store updates.
#
# Usage (from apps/pos/android):
#   ./scripts/generate-keystore.sh [--alias gastrocore] [--validity 10000]
#
# Environment variable STORE_PASSWORD / KEY_PASSWORD can be set to
# skip the interactive prompt (CI bootstrap).
set -euo pipefail

cd "$(dirname "$0")/.."

ALIAS="gastrocore"
VALIDITY="10000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --alias)    ALIAS="$2";    shift 2;;
    --validity) VALIDITY="$2"; shift 2;;
    *)          echo "unknown flag: $1" >&2; exit 2;;
  esac
done

OUT="app/gastrocore-release.jks"

if [[ -f "$OUT" ]]; then
  echo "refusing to overwrite existing keystore: $OUT" >&2
  echo "rename / move it manually if you really want to regenerate." >&2
  exit 1
fi

mkdir -p app

echo "generating $OUT (alias=$ALIAS, validity=${VALIDITY}d)"
keytool -genkey -v \
  -keystore "$OUT" \
  -keyalg RSA -keysize 2048 \
  -validity "$VALIDITY" \
  -alias "$ALIAS" \
  -dname "CN=GastroCore, OU=Engineering, O=2tech, L=Zurich, ST=ZH, C=CH"

echo
echo "next steps:"
echo "  1. cp key.properties.template key.properties"
echo "  2. edit key.properties with the passwords you just set"
echo "  3. BACK UP $OUT to 1Password / Vault"
echo "  4. flutter build apk --flavor pos --release"
