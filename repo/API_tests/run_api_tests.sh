#!/usr/bin/env bash

set +e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUMMARY_FILE="$ROOT_DIR/API_tests/.summary"
API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:${API_PORT:-3000}}"

TOTAL=0
PASSED=0
FAILED=0

write_summary() {
  cat >"$SUMMARY_FILE" <<EOF
TOTAL=$TOTAL
PASSED=$PASSED
FAILED=$FAILED
EOF
}

fail_fast_unreachable() {
  echo "[API][FAIL] backend_reachability"
  echo "  reason: backend server is not reachable at $API_BASE_URL"
  echo "  hint: start backend before running API tests"
  TOTAL=1
  PASSED=0
  FAILED=1
  write_summary
  exit 1
}

if ! command -v curl >/dev/null 2>&1; then
  echo "[API][FAIL] prerequisites"
  echo "  reason: curl command is required"
  TOTAL=1
  PASSED=0
  FAILED=1
  write_summary
  exit 1
fi

if ! curl -sS -m 5 "$API_BASE_URL/health" >/dev/null 2>&1; then
  fail_fast_unreachable
fi

run_status_test() {
  local name="$1"
  local method="$2"
  local path="$3"
  local expected_status="$4"
  local payload="${5:-}"

  TOTAL=$((TOTAL + 1))
  local body_file
  body_file="$(mktemp)"

  local status
  if [ -n "$payload" ]; then
    status="$(curl -sS -m 10 -o "$body_file" -w "%{http_code}" -X "$method" "$API_BASE_URL$path" -H "Content-Type: application/json" --data "$payload")"
  else
    status="$(curl -sS -m 10 -o "$body_file" -w "%{http_code}" -X "$method" "$API_BASE_URL$path")"
  fi
  local curl_exit=$?

  if [ "$curl_exit" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "[API][FAIL] $name"
    echo "  reason: request failed with curl exit code $curl_exit"
    rm -f "$body_file"
    return
  fi

  if [ "$status" = "$expected_status" ]; then
    PASSED=$((PASSED + 1))
    echo "[API][PASS] $name"
  else
    FAILED=$((FAILED + 1))
    echo "[API][FAIL] $name"
    echo "  reason: expected HTTP $expected_status but got $status"
    echo "  log snippet:"
    sed -n '1,10p' "$body_file"
  fi

  rm -f "$body_file"
}

echo "API TESTS against $API_BASE_URL"

run_status_test "health_endpoint" "GET" "/health" "200"
run_status_test "auth_register_missing_fields" "POST" "/api/v1/auth/register" "400" '{"username":"ab"}'
run_status_test "follows_mine_requires_auth" "GET" "/api/v1/follows/mine" "401"
run_status_test "reviews_mine_requires_auth" "GET" "/api/v1/reviews/mine" "401"
run_status_test "feed_requires_auth" "GET" "/api/v1/feed?limit=1" "401"
run_status_test "unknown_route_not_found" "GET" "/api/v1/does-not-exist" "404"

echo ""
echo "API TEST SUMMARY"
echo "TOTAL=$TOTAL"
echo "PASSED=$PASSED"
echo "FAILED=$FAILED"

write_summary

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi

exit 0
