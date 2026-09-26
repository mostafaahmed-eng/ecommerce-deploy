#!/usr/bin/env bash
#
# Post-deployment smoke tests for the low-cost EC2 Docker Compose profile.
#
# Why this exists: the first AWS deployment passed a health check while
# checkout and the owner dashboard were completely broken (404). A health-only
# check is therefore not enough - these tests walk the real route chain
#   browser -> nginx -> API gateway -> service
# and fail on 404/500/502/503 for every path the storefront depends on.
#
# Deliberate design points:
#   * NO credentials are used or required, so nothing sensitive can leak into
#     the GitHub Actions log.
#   * 400/401 from a protected or validating endpoint is a PASS: it proves the
#     route exists, is reached, and is correctly guarded.
#   * 404 is always a FAIL.
#
# Usage:
#   scripts/smoke-test.sh                      # http://127.0.0.1:80
#   scripts/smoke-test.sh --base-url http://1.2.3.4
#   scripts/smoke-test.sh --verbose
#
set -uo pipefail

BASE_URL="http://127.0.0.1:80"
VERBOSE=0
CONNECT_TIMEOUT="${SMOKE_CONNECT_TIMEOUT:-5}"
MAX_TIME="${SMOKE_MAX_TIME:-20}"

log()  { printf '[smoke] %s\n' "$*"; }
die()  { printf '[smoke] FAIL: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url) BASE_URL="${2:?}"; shift ;;
    --verbose|-v) VERBOSE=1 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

BASE_URL="${BASE_URL%/}"
command -v curl >/dev/null 2>&1 || die "curl is not installed"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
CHECKS=0

# request METHOD PATH EXPECTED_CODES DESCRIPTION [body-file]
request() {
  local method="$1" path="$2" expected="$3" description="$4" body="${5:-}"
  CHECKS=$((CHECKS + 1))

  local args=(-sS -o "$WORK/out" -w '%{http_code}'
              --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME"
              -X "$method" "$BASE_URL$path")
  [ -n "$body" ] && args+=(--data-binary "@$body")

  local code
  code="$(curl "${args[@]}" 2>/dev/null)" || code="000"

  local ok=0
  case ",$expected," in
    *",$code,"*) ok=1 ;;
  esac
  # Anything that says "the route is not wired" is always a hard failure,
  # even if it happened to be listed as acceptable.
  case "$code" in
    404|502|503) ok=0 ;;
  esac

  if [ "$ok" -eq 1 ]; then
    printf '[smoke] PASS  %-6s %-26s -> %s (%s)\n' "$method" "$path" "$code" "$description"
  else
    printf '[smoke] FAIL  %-6s %-26s -> %s, expected one of [%s] (%s)\n' \
           "$method" "$path" "$code" "$expected" "$description" >&2
    if [ "$VERBOSE" -eq 1 ]; then
      sed -n '1,6p' "$WORK/out" | sed 's/^/[smoke]        | /' >&2
    fi
    FAILURES=$((FAILURES + 1))
  fi
  return 0
}

log "target: $BASE_URL"

# --- Layer 1: the reverse proxy itself --------------------------------------
request GET  /nginx-health               "200"        "nginx liveness"

# --- Layer 2: storefront -----------------------------------------------------
request GET  /                            "200"        "storefront renders"
request GET  /styles.css                  "200"        "static assets served"

# --- Layer 3: API gateway fan-out -------------------------------------------
# Each of these proves one more hop of nginx -> gateway -> service is wired.
request GET  /api/health                  "200"        "gateway -> backend"
request GET  /api/products                "200"        "gateway -> product"
request GET  "/api/search?q=phone"        "200"        "gateway -> search"
request GET  /api/categories              "200"        "gateway -> product categories"
request GET  /api/cart/smoke-test-user    "200"        "gateway -> cart"

# --- Layer 4: payment (the route that 404'd on the first deployment) ---------
# 200 proves the config endpoint answers; the POST must reach validation
# (400) rather than the router (404).
request GET  /api/payments/config         "200"        "gateway -> payment config"
printf '%s' '{"fullName":"","phone":"","shippingAddress":"","city":""}' > "$WORK/order.json"
request POST /api/payments/orders         "400,201"    "payment order route exists"

# --- Layer 5: owner dashboard ------------------------------------------------
# 401 is the SUCCESS case: the route exists and authentication is enforced.
request GET  /api/admin/session           "401,200"    "admin route exists + is guarded"
request GET  /api/admin/orders            "401,200"    "admin order list guarded"
request GET  /api/contact                 "200"        "public contact config"

printf '\n'
if [ "$FAILURES" -gt 0 ]; then
  die "$FAILURES of $CHECKS smoke checks failed"
fi
log "all $CHECKS smoke checks passed"
