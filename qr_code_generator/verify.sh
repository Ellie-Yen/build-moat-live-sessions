#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://localhost:8000"
PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }

pass() { green "  PASS: $1"; ((PASS++)); }
fail() { red   "  FAIL: $1"; ((FAIL++)); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (got: $actual)"
  else
    fail "$label (expected: $expected, got: $actual)"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    pass "$label"
  else
    fail "$label (expected to contain '$needle', got: $haystack)"
  fi
}

echo "=== QR Code Generator Tests ==="
echo ""

# ── 1. Create QR code ──────────────────────────────────────────────────────────
echo "--- 1. Create QR code ---"
CREATE_RESP=$(curl -s -w '\n%{http_code}' -X POST "$BASE_URL/api/qr/create" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}')
CREATE_BODY=$(echo "$CREATE_RESP" | head -n -1)
CREATE_STATUS=$(echo "$CREATE_RESP" | tail -n 1)

assert_eq "POST /api/qr/create → 200" "200" "$CREATE_STATUS"
assert_contains "response has 'token'"     '"token"'     "$CREATE_BODY"
assert_contains "response has 'short_url'" '"short_url"' "$CREATE_BODY"
assert_contains "response has 'qr_code_url'" '"qr_code_url"' "$CREATE_BODY"
assert_contains "response has 'original_url'" '"original_url"' "$CREATE_BODY"

TOKEN=$(echo "$CREATE_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
echo "  token: $TOKEN"
echo ""

# ── 2. Redirect ─────────────────────────────────────────────────────────────────
echo "--- 2. Redirect ---"
REDIRECT_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/r/$TOKEN")
assert_eq "GET /r/{token} → 302" "302" "$REDIRECT_CODE"
echo ""

# ── 3. Get info ──────────────────────────────────────────────────────────────────
echo "--- 3. Get info ---"
INFO_RESP=$(curl -s -w '\n%{http_code}' "$BASE_URL/api/qr/$TOKEN")
INFO_BODY=$(echo "$INFO_RESP" | head -n -1)
INFO_STATUS=$(echo "$INFO_RESP" | tail -n 1)

assert_eq "GET /api/qr/{token} → 200" "200" "$INFO_STATUS"
assert_contains "info body has token" "$TOKEN" "$INFO_BODY"
echo ""

# ── 4. Update target URL ──────────────────────────────────────────────────────
echo "--- 4. Update target URL ---"
UPDATE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$BASE_URL/api/qr/$TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://new-url.com"}')
assert_eq "PATCH /api/qr/{token} → 200" "200" "$UPDATE_STATUS"
echo ""

# ── 5. Redirect goes to new URL ───────────────────────────────────────────────
echo "--- 5. Redirect after update ---"
REDIRECT_URL=$(curl -s -o /dev/null -w "%{redirect_url}" "$BASE_URL/r/$TOKEN")
assert_contains "redirect_url contains new-url.com" "new-url.com" "$REDIRECT_URL"
echo ""

# ── 6. QR code image ──────────────────────────────────────────────────────────
echo "--- 6. QR code image ---"
IMAGE_META=$(curl -s -o /dev/null -w "%{http_code} %{content_type}" "$BASE_URL/api/qr/$TOKEN/image")
IMAGE_CODE=$(echo "$IMAGE_META" | awk '{print $1}')
IMAGE_CT=$(echo "$IMAGE_META" | awk '{print $2}')

assert_eq "GET /api/qr/{token}/image → 200" "200" "$IMAGE_CODE"
assert_contains "content-type is image/png" "image/png" "$IMAGE_CT"
echo ""

# ── 7. Analytics ──────────────────────────────────────────────────────────────
echo "--- 7. Analytics ---"
ANALYTICS_RESP=$(curl -s -w '\n%{http_code}' "$BASE_URL/api/qr/$TOKEN/analytics")
ANALYTICS_BODY=$(echo "$ANALYTICS_RESP" | head -n -1)
ANALYTICS_STATUS=$(echo "$ANALYTICS_RESP" | tail -n 1)

assert_eq "GET /api/qr/{token}/analytics → 200" "200" "$ANALYTICS_STATUS"
assert_contains "analytics has 'total_scans'" '"total_scans"' "$ANALYTICS_BODY"
assert_contains "analytics has 'scans_by_day'" '"scans_by_day"' "$ANALYTICS_BODY"
echo ""

# ── 8. Delete ─────────────────────────────────────────────────────────────────
echo "--- 8. Delete ---"
DELETE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/api/qr/$TOKEN")
assert_eq "DELETE /api/qr/{token} → 200" "200" "$DELETE_STATUS"
echo ""

# ── 9. Redirect after delete → 410 ───────────────────────────────────────────
echo "--- 9. Redirect after delete ---"
AFTER_DELETE_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/r/$TOKEN")
assert_eq "GET /r/{token} after delete → 410" "410" "$AFTER_DELETE_CODE"
echo ""

# ── 10. Non-existent token → 404 ─────────────────────────────────────────────
echo "--- 10. Non-existent token ---"
NOT_FOUND_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/r/INVALID_TOKEN_XYZ")
assert_eq "GET /r/INVALID_TOKEN_XYZ → 404" "404" "$NOT_FOUND_CODE"
echo ""

# ── 11. Expiration (optional bonus) ──────────────────────────────────────────
echo "--- 11. Expiration (create with past expiry) ---"
EXPIRED_RESP=$(curl -s -w '\n%{http_code}' -X POST "$BASE_URL/api/qr/create" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com", "expires_at": "2000-01-01T00:00:00Z"}')
EXPIRED_BODY=$(echo "$EXPIRED_RESP" | head -n -1)
EXPIRED_CREATE_STATUS=$(echo "$EXPIRED_RESP" | tail -n 1)

if [[ "$EXPIRED_CREATE_STATUS" == "200" ]]; then
  EXPIRED_TOKEN=$(echo "$EXPIRED_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  EXPIRED_REDIRECT=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/r/$EXPIRED_TOKEN")
  assert_eq "GET /r/{expired_token} → 410" "410" "$EXPIRED_REDIRECT"
else
  pass "server rejected expired-at-creation request ($EXPIRED_CREATE_STATUS) — acceptable"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "==========================="
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -eq 0 ]]; then
  green "All tests passed!"
  exit 0
else
  red "$FAIL test(s) failed."
  exit 1
fi
