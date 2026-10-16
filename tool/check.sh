#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$project_root/.tools/flutter/bin:$PATH"
cd "$project_root"
flutter pub get
dart format lib test tool/simulate.dart
flutter analyze --fatal-infos
flutter test
dart tool/simulate.dart --days 30 --seed 42
dart tool/simulate.dart --days 10000 --seed 42
flutter build web --release
