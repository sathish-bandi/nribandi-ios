#!/usr/bin/env bash
# Verify the Local NRIBANDI backend is reachable from this Mac.
set -euo pipefail

BASE_URL="${NRIBANDI_API_BASE_URL:-http://127.0.0.1:8082}"
HEALTH_URL="${BASE_URL%/}/actuator/health"

echo "Checking backend: ${HEALTH_URL}"
if curl -sf --max-time 5 "${HEALTH_URL}" >/dev/null; then
  echo "Backend is UP."
  curl -s "${HEALTH_URL}" || true
  echo
  exit 0
fi

echo "Backend is NOT reachable at ${BASE_URL}"
echo
echo "In the backend repo (rental-property-app), run:"
echo "  cp .env.local.example .env"
echo "  chmod +x scripts/*.sh"
echo "  ./scripts/local-up.sh"
echo
echo "Or double-click START-ON-MAC.command in that repo."
exit 1
