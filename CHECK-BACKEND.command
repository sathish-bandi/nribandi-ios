#!/bin/bash
# Double-click to test whether the Local backend is up.
set -euo pipefail
cd "$(dirname "$0")"
chmod +x scripts/*.sh CHECK-BACKEND.command 2>/dev/null || true
./scripts/check-backend.sh || true
echo
read -r -p "Press Return to close…"
