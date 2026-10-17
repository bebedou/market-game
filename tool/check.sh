#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$project_root/.tools/flutter/bin:$PATH"
cd "$project_root"
flutter pub get
dart format lib test tool/simulate.dart tool/replay_check.dart
flutter analyze --fatal-infos
flutter test
dart tool/simulate.dart --days 30 --seed 42
dart tool/simulate.dart --days 10000 --seed 42
mkdir -p build/engine-check
dart tool/replay_check.dart > build/engine-check/vm.json
dart compile js tool/replay_check.dart -o build/engine-check/replay.js
node build/engine-check/replay.js > build/engine-check/web.json
cmp build/engine-check/vm.json build/engine-check/web.json
echo "Dart VM and JavaScript states match after 365 days."
flutter build web --release
