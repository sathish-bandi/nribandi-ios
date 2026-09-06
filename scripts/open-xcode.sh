#!/usr/bin/env bash
# Open the NRIBANDI iOS project in Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="${ROOT}/Nribandi.xcodeproj"

if [[ ! -d "${PROJ}" ]]; then
  echo "Cannot find ${PROJ}"
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1 && [[ ! -d /Applications/Xcode.app ]]; then
  echo "Xcode is not installed. Install it from the Mac App Store, then retry."
  exit 1
fi

echo "Opening ${PROJ}"
open "${PROJ}"
