#!/bin/bash
# Double-click in Finder to prepare Local iOS run (check backend + open Xcode).
set -euo pipefail
cd "$(dirname "$0")"
chmod +x scripts/*.sh START-ON-MAC.command CHECK-BACKEND.command 2>/dev/null || true

osascript -e 'display notification "Checking backend and opening Xcode…" with title "NRIBANDI iOS"' 2>/dev/null || true

if ! ./scripts/check-backend.sh; then
  osascript -e 'display dialog "Backend is not running on http://127.0.0.1:8082.\n\nOpen the rental-property-app folder and run START-ON-MAC.command (or ./scripts/local-up.sh), then try again." buttons {"OK"} default button "OK" with icon caution' 2>/dev/null || true
  read -r -p "Press Return to close…"
  exit 1
fi

./scripts/open-xcode.sh

cat <<'TXT'

Xcode is opening.

Next:
  1. Choose an iPhone Simulator
  2. Press Run (⌘R)
  3. Environment: Local
  4. Login: admin@nribandi.local / Nribandi@123

TXT
read -r -p "Press Return to close…"
