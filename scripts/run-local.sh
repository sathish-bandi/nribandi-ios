#!/usr/bin/env bash
# Local workflow helper for the NRIBANDI iOS app.
# Checks backend health, then opens Xcode. Build/Run still happens in Xcode (⌘R).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

chmod +x scripts/*.sh START-ON-MAC.command CHECK-BACKEND.command 2>/dev/null || true

echo "=== NRIBANDI iOS — Local ==="
echo "1) Checking Local backend on http://127.0.0.1:8082 ..."
if ! ./scripts/check-backend.sh; then
  exit 1
fi

echo
echo "2) Opening Xcode…"
./scripts/open-xcode.sh

echo
echo "3) In Xcode:"
echo "   • Select an iPhone Simulator"
echo "   • Press Run (⌘R)"
echo "   • Keep environment = Local"
echo "   • Login: admin@nribandi.local / Nribandi@123"
echo
