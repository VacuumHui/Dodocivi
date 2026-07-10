#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -d android ]]; then
  BACKUP="$(mktemp -d)"
  trap 'rm -rf "$BACKUP"' EXIT

  cp -R lib "$BACKUP/lib"
  cp -R test "$BACKUP/test"
  cp pubspec.yaml "$BACKUP/pubspec.yaml"
  cp analysis_options.yaml "$BACKUP/analysis_options.yaml"

  flutter create \
    --platforms=android \
    --org=com.example \
    --project-name=sdxl_collector \
    --no-pub \
    .

  rm -rf lib test
  cp -R "$BACKUP/lib" lib
  cp -R "$BACKUP/test" test
  cp "$BACKUP/pubspec.yaml" pubspec.yaml
  cp "$BACKUP/analysis_options.yaml" analysis_options.yaml
fi

python3 tool/configure_android.py
flutter pub get
