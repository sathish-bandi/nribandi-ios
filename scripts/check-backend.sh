#!/usr/bin/env bash
# Verify the Local NRIBANDI backend is reachable and has demo data.
set -euo pipefail

BASE_URL="${NRIBANDI_API_BASE_URL:-http://127.0.0.1:8082}"
HEALTH_URL="${BASE_URL%/}/actuator/health"
EMAIL="${NRIBANDI_ADMIN_EMAIL:-admin@nribandi.local}"
PASSWORD="${NRIBANDI_ADMIN_PASSWORD:-Nribandi@123}"

echo "Checking backend: ${HEALTH_URL}"
if ! curl -sf --max-time 5 "${HEALTH_URL}" >/dev/null; then
  echo "Backend is NOT reachable at ${BASE_URL}"
  echo
  echo "In the backend repo (rental-property-app), run:"
  echo "  ./scripts/local-up.sh"
  echo "Or double-click START-ON-MAC.command"
  exit 1
fi

echo "Backend is UP."
curl -s "${HEALTH_URL}" || true
echo
echo

echo "Logging in as ${EMAIL} ..."
login_json="$(curl -sf --max-time 10 -X POST "${BASE_URL%/}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}" || true)"

if [[ -z "${login_json}" ]]; then
  echo "Login FAILED. Is the password still Nribandi@123?"
  echo "If seed never ran, run: ./scripts/local-seed.sh  (or SEED-ON-MAC.command)"
  exit 1
fi

token="$(printf '%s' "${login_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("accessToken") or d.get("access_token") or "")')"
if [[ -z "${token}" ]]; then
  echo "Login response had no accessToken:"
  echo "${login_json}"
  exit 1
fi

echo "Fetching dashboard summary ..."
summary="$(curl -sf --max-time 10 "${BASE_URL%/}/api/v1/dashboard/summary" \
  -H "Authorization: Bearer ${token}")"

printf '%s' "${summary}" | python3 -c '
import json, sys
s = json.load(sys.stdin)
props = s.get("totalProperties", 0)
units = s.get("totalUnits", 0)
print(f"totalProperties = {props}")
print(f"totalUnits      = {units}")
print(f"occupiedUnits   = {s.get(\"occupiedUnits\", 0)}")
print(f"vacantUnits     = {s.get(\"vacantUnits\", 0)}")
print(f"newEnquiries    = {s.get(\"newEnquiries\", 0)}")
if props == 0 or units == 0:
    print()
    print("EMPTY DATA: the API works, but demo rows are missing.")
    print("In rental-property-app on your Mac, run:")
    print("  ./scripts/local-seed.sh")
    print("Or double-click SEED-ON-MAC.command")
    print("You must see non-zero property/unit counts in that Terminal window.")
    raise SystemExit(1)
print()
print("Demo data looks good. Swipe down on the iOS Dashboard to refresh.")
'
