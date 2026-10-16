#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk_dir="$project_root/.tools/flutter"
revision="$(tr -d '\r\n' < "$project_root/.flutter-revision")"
version="$(tr -d '\r\n' < "$project_root/.flutter-version")"
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Invalid Flutter revision in .flutter-revision' >&2
  exit 1
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Invalid stable Flutter version in .flutter-version' >&2
  exit 1
fi

mkdir -p "$project_root/.tools"
if [[ ! -d "$sdk_dir/.git" ]]; then
  git init "$sdk_dir"
  git -C "$sdk_dir" remote add origin https://github.com/flutter/flutter.git
fi

installed_revision="$(git -C "$sdk_dir" rev-parse HEAD 2>/dev/null || true)"
installed_tag="$(git -C "$sdk_dir" rev-parse -q --verify "refs/tags/$version^{commit}" 2>/dev/null || true)"
if [[ "$installed_revision" != "$revision" || "$installed_tag" != "$revision" ]]; then
  # Flutter needs its release tag to resolve SDK version constraints correctly.
  git -C "$sdk_dir" fetch --depth 1 origin "refs/tags/$version:refs/tags/$version"
  resolved_revision="$(git -C "$sdk_dir" rev-parse "refs/tags/$version^{commit}")"
  if [[ "$resolved_revision" != "$revision" ]]; then
    echo 'Flutter release tag does not match the pinned revision.' >&2
    exit 1
  fi
  git -C "$sdk_dir" checkout -B stable "$revision"
  rm -f "$sdk_dir/bin/cache/flutter.version.json"
fi

export PATH="$sdk_dir/bin:$PATH"
cd "$project_root"
flutter config --no-analytics --enable-web --enable-android
flutter precache --web
flutter --version

# Generate native boilerplate using this exact Flutter SDK. Copy only the Android
# launcher, so existing app code, tests, and web files cannot be overwritten.
if [[ ! -f android/app/src/main/AndroidManifest.xml ]]; then
  template_dir="$(mktemp -d)"
  trap 'rm -rf "$template_dir"' EXIT
  flutter create --no-pub --platforms=android --org=com.bebedou \
    --project-name=market_game "$template_dir/market_game"
  cp -R "$template_dir/market_game/android" "$project_root/android"
fi

flutter pub get
echo 'Setup complete. Run: bash tool/preview.sh'
