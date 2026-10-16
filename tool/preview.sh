#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
if [[ ! -x .tools/flutter/bin/flutter ]]; then
  echo 'First run: bash tool/setup.sh' >&2
  exit 1
fi

exec .tools/flutter/bin/flutter run -d web-server \
  --web-hostname=0.0.0.0 --web-port=8080 "$@"
