#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$project_root/.tools/flutter/bin:$PATH"
cd "$project_root"
flutter pub get
dart format lib test
flutter analyze --fatal-infos
flutter test
flutter build web --release
