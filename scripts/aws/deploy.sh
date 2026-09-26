#!/usr/bin/env bash
#
# Host-side deployment for the low-cost EC2 Docker Compose profile.
#
# Invoked by GitHub Actions through AWS Systems Manager Run Command:
#
#   aws ssm send-command --target i-0123456789abcdef0 \
#     --document-name AWS-RunShellScript \
#     --parameters 'commands=["bash /opt/ecommerce/compose/deploy.sh --sha <GITHUB_SHA> ..."]'
#
# It never needs SSH. It never prints secret values.
#
# Deployment metadata (section 17 of DEPLOYMENT_SUMMARY.md):
#
#   /opt/ecommerce/.deployment/current    the SHA currently running
#   /opt/ecommerce/.deployment/previous   the last known-good SHA (rollback target)
#
# Usage:
#   deploy.sh --sha <git-sha> --repo <owner>/<name> [options]
#   deploy.sh --rollback
#
# Options:
#   --sha SHA           image tag / commit SHA to deploy (required unless --rollback)
#   --repo OWNER/REPO   GitHub repository used to fetch the pinned config files
#   --ref REF           ref used to fetch config files (default: the SHA itself)
#   --base-url URL      PUBLIC_BASE_URL, required for correct CORS in production
#   --http-port N       host port for nginx (default 80)
#   --https-port N      host port for nginx TLS (default 443)
#   --rollback          redeploy the SHA recorded in .deployment/previous
#   --skip-config       do not re-download compose/nginx from GitHub
#   --skip-ssm          do not re-read SSM Parameter Store
#   --no-rollback       fail without attempting a rollback
#
set -euo pipefail

ROOT="${ECOMMERCE_HOME:-/opt/ecommerce}"
COMPOSE_DIR="$ROOT/compose"
DEPLOY_DIR="$ROOT/.deployment"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.prod.yml"
ENV_FILE="$ROOT/.env.production"
COMPOSE_DOTENV="$COMPOSE_DIR/.env"

SHA=""
REPO=""
REF=""
BASE_URL=""
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
DO_ROLLBACK=0
SKIP_CONFIG=0
SKIP_SSM=0
ALLOW_ROLLBACK=1
RETRIES="${DEPLOY_RETRIES:-6}"
WAIT_ATTEMPTS="${DEPLOY_WAIT_ATTEMPTS:-40}"

log() { printf '[deploy] %s\n' "$*"; }
err() { printf '[deploy] ERROR: %s\n' "$*" >&2; }

usage() { sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --sha)          SHA="${2:?}"; shift ;;
    --repo)         REPO="${2:?}"; shift ;;
    --ref)          REF="${2:?}"; shift ;;
    --base-url)     BASE_URL="${2:?}"; shift ;;
    --http-port)    HTTP_PORT="${2:?}"; shift ;;
    --https-port)   HTTPS_PORT="${2:?}"; shift ;;
    --rollback)     DO_ROLLBACK=1 ;;
    --skip-config)  SKIP_CONFIG=1 ;;
    --skip-ssm)     SKIP_SSM=1 ;;
    --no-rollback)  ALLOW_ROLLBACK=0 ;;
    -h|--help)      usage; exit 0 ;;
    *) err "unknown argument: $1"; usage; exit 2 ;;
  esac
  shift
done

command -v docker >/dev/null 2>&1 || { err "docker is not installed"; exit 1; }
docker compose version >/dev/null 2>&1 || { err "the docker compose v2 plugin is required"; exit 1; }

mkdir -p "$ROOT" "$COMPOSE_DIR" "$DEPLOY_DIR" \
         "$ROOT/data" "$ROOT/uploads/receipts" "$ROOT/letsencrypt" "$ROOT/certbot-www"

read_state() { [ -f "$1" ] && tr -d '[:space:]' < "$1" || echo ""; }
CURRENT="$(read_state "$DEPLOY_DIR/current")"
PREVIOUS="$(read_state "$DEPLOY_DIR/previous")"

# --- Resolve the target SHA --------------------------------------------------
if [ "$DO_ROLLBACK" -eq 1 ]; then
  SHA="$PREVIOUS"
  [ -n "$SHA" ] || { err "no previous release recorded - nothing to roll back to"; exit 1; }
  [ "$SHA" = "$CURRENT" ] && { err "previous and current are the same SHA"; exit 1; }
  log "rollback requested: current=${CURRENT:-none} -> target=$SHA"
  SKIP_CONFIG=1
fi

[ -n "$SHA" ] || { err "--sha is required (or use --rollback)"; exit 2; }
[ "$SHA" != "$CURRENT" ] || log "WARNING: redeploying the same SHA ($SHA)"

REF="${REF:-$SHA}"
if [ -z "$BASE_URL" ] && [ -f "$COMPOSE_DOTENV" ]; then
  BASE_URL="$(grep -E '^PUBLIC_BASE_URL=' "$COMPOSE_DOTENV" | head -n1 | cut -d= -f2- || true)"
fi

# --- 1. Fetch pinned deployment configuration --------------------------------
if [ "$SKIP_CONFIG" -eq 0 ]; then
  [ -n "$REPO" ] || { err "--repo OWNER/NAME is required to fetch configuration"; exit 2; }
  command -v curl >/dev/null 2>&1 || { err "curl is not installed"; exit 1; }
  RAW="https://raw.githubusercontent.com/$REPO/$REF"
  log "fetching pinned configuration for $REF"

  fetch() {
    # $1 = remote path, $2 = local path
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fsSL --retry 3 -H "Authorization: Bearer $GITHUB_TOKEN" "$RAW/$1" -o "$2"
    else
      curl -fsSL --retry 3 "$RAW/$1" -o "$2"
    fi
  }

  TMP_CFG="$(mktemp -d)"
  trap 'rm -rf "$TMP_CFG"' EXIT
  fetch "docker-compose.prod.yml" "$TMP_CFG/docker-compose.prod.yml"
  mkdir -p "$TMP_CFG/nginx/conf.d" "$TMP_CFG/nginx/snippets"
  fetch "nginx/production.conf"           "$TMP_CFG/nginx/production.conf"
  fetch "nginx/https.conf.tpl"            "$TMP_CFG/nginx/https.conf.tpl"
  fetch "nginx/conf.d/00-default.conf"    "$TMP_CFG/nginx/conf.d/00-default.conf"
  fetch "nginx/snippets/proxy-common.conf" "$TMP_CFG/nginx/snippets/proxy-common.conf"
  fetch "scripts/smoke-test.sh"           "$TMP_CFG/smoke-test.sh"
  fetch "scripts/aws/load-ssm-env.sh"     "$TMP_CFG/load-ssm-env.sh"

  # The live HTTPS server block must survive a config refresh, otherwise a
  # redeploy would silently drop the certificate that was issued earlier.
  if [ -f "$COMPOSE_DIR/nginx/conf.d/443-ssl.conf" ]; then
    cp -f "$COMPOSE_DIR/nginx/conf.d/443-ssl.conf" "$TMP_CFG/nginx/conf.d/443-ssl.conf"
    log "preserving existing conf.d/443-ssl.conf"
  fi

  cp -f "$TMP_CFG/docker-compose.prod.yml" "$COMPOSE_FILE"
  rm -rf "$COMPOSE_DIR/nginx"
  cp -R "$TMP_CFG/nginx" "$COMPOSE_DIR/nginx"
  install -m 0755 "$TMP_CFG/smoke-test.sh"      "$COMPOSE_DIR/smoke-test.sh"
  install -m 0755 "$TMP_CFG/load-ssm-env.sh"    "$COMPOSE_DIR/load-ssm-env.sh"
else
  log "skipping configuration refresh"
fi

[ -f "$COMPOSE_FILE" ] || { err "$COMPOSE_FILE is missing"; exit 1; }

# --- 2. Compose interpolation file (non-secret) ------------------------------
# Written every run so port / base-URL changes take effect. Secrets live in
# $ENV_FILE and are attached to the payment service through env_file only.
# GHCR_OWNER / PUBLIC_BASE_URL are preserved from the previous run when the
# caller (a rollback, for instance) did not supply them.
EXISTING_OWNER=""
EXISTING_BASE="$BASE_URL"
if [ -f "$COMPOSE_DOTENV" ]; then
  EXISTING_OWNER="$(grep -E '^GHCR_OWNER=' "$COMPOSE_DOTENV" | head -n1 | cut -d= -f2- || true)"
  [ -n "$EXISTING_BASE" ] || EXISTING_BASE="$(grep -E '^PUBLIC_BASE_URL=' "$COMPOSE_DOTENV" | head -n1 | cut -d= -f2- || true)"
fi
# GHCR_OWNER is the *registry-qualified* namespace, because docker-compose.prod.yml
# references images as "${GHCR_OWNER}/ecommerce-<service>". ${REPO%%/*} is only the
# bare account name, which Docker resolves against docker.io - so the old default
# produced `mostafaahmed-eng/ecommerce-api:<sha>` and `compose pull` failed with:
#
#   denied: requested access to the resource is denied
#   unauthorized: authentication required
#
# Verified against the host: the bare name is denied, while
# `ghcr.io/mostafaahmed-eng/ecommerce-api:<sha>` resolves anonymously (the
# packages are public, so no `docker login` is needed). The empty -> EXISTING_OWNER
# fallback below is unchanged; only the registry qualification is new.
GHCR_OWNER_VALUE="${GHCR_OWNER:-}"
[ -n "$GHCR_OWNER_VALUE" ] || GHCR_OWNER_VALUE="${REPO%%/*}"
[ -n "$GHCR_OWNER_VALUE" ] || GHCR_OWNER_VALUE="$EXISTING_OWNER"
case "$GHCR_OWNER_VALUE" in
  "")    ;;                            # nothing to qualify
  */*)   ;;                            # already registry-qualified (ghcr.io/owner)
  *)     GHCR_OWNER_VALUE="ghcr.io/$GHCR_OWNER_VALUE" ;;  # tolerate a bare owner
esac
BASE_URL="${EXISTING_BASE:-}"

{
  printf '# Generated by deploy.sh - non-secret compose settings.\n'
  printf 'IMAGE_TAG=%s\n' "$SHA"
  printf 'GHCR_OWNER=%s\n' "$GHCR_OWNER_VALUE"
  printf 'HTTP_PORT=%s\n' "$HTTP_PORT"
  printf 'HTTPS_PORT=%s\n' "$HTTPS_PORT"
  printf 'PUBLIC_BASE_URL=%s\n' "$BASE_URL"
  printf 'NGINX_CONF_DIR=%s/nginx\n' "$COMPOSE_DIR"
  printf 'DATA_DIR_HOST=%s/data\n' "$ROOT"
  printf 'RECEIPTS_DIR_HOST=%s/uploads/receipts\n' "$ROOT"
  printf 'CERTBOT_WWW=%s/certbot-www\n' "$ROOT"
  printf 'LETS_ENCRYPT_DIR=%s/letsencrypt\n' "$ROOT"
  printf 'APP_ENV_FILE=%s\n' "$ENV_FILE"
} > "$COMPOSE_DOTENV"

# --- 3. Secrets from Parameter Store ----------------------------------------
if [ "$SKIP_SSM" -eq 0 ]; then
  if [ -f "$COMPOSE_DIR/load-ssm-env.sh" ]; then
    bash "$COMPOSE_DIR/load-ssm-env.sh" || err "SSM parameter load failed; continuing with existing $ENV_FILE"
  fi
else
  log "skipping SSM parameter refresh"
fi

if [ ! -s "$ENV_FILE" ]; then
  err "$ENV_FILE is missing or empty."
  err "Run scripts/aws/load-ssm-env.sh (or create the /ecommerce/* parameters) first."
  exit 1
fi
chmod 600 "$ENV_FILE"

# Host directories must be writable by the non-root container user (uid 1000).
chown -R 1000:1000 "$ROOT/data" "$ROOT/uploads" 2>/dev/null || true

# --- 4. Record release metadata BEFORE touching running containers -----------
printf '%s\n' "${CURRENT:-unknown}" > "$DEPLOY_DIR/previous"
printf '%s\n' "$SHA"                 > "$DEPLOY_DIR/current"
log "release: previous=${CURRENT:-none} current=$SHA"

cd "$COMPOSE_DIR"

compose() { docker compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_DOTENV" "$@"; }

diagnostics() {
  err "----- non-secret diagnostics -----"
  compose ps -a || true
  for service in nginx api frontend payment; do
    err "--- last 40 log lines: $service ---"
    compose logs --no-color --tail=40 "$service" 2>&1 | sed -E 's/(PASSWORD|SECRET|TOKEN|PASS)=[^ ]*/\1=<redacted>/g' >&2 || true
  done
  err "----- end diagnostics -----"
}

wait_healthy() {
  local attempt=0
  while [ "$attempt" -lt "$WAIT_ATTEMPTS" ]; do
    local pending
    pending="$(compose ps --format '{{.Service}} {{.Health}}' 2>/dev/null \
               | awk '$2 != "healthy" && $2 != "" { print $1 }' | tr '\n' ' ')"
    if [ -z "${pending// /}" ]; then
      log "all containers healthy"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 5
  done
  err "containers still unhealthy after $((WAIT_ATTEMPTS * 5))s"
  return 1
}

rollback() {
  [ "$ALLOW_ROLLBACK" -eq 1 ] || { err "rollback disabled by --no-rollback"; return 1; }
  [ -n "$PREVIOUS" ] || { err "no previous SHA recorded - cannot roll back"; return 1; }
  [ "$PREVIOUS" != "$SHA" ] || { err "previous SHA equals the failed SHA - nothing safe to roll back to"; return 1; }

  log "ROLLING BACK $SHA -> $PREVIOUS"
  sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=$PREVIOUS|" "$COMPOSE_DOTENV"
  # .deployment/current now points at what is actually running. .deployment/
  # previous is deliberately left untouched: once current == previous a second
  # rollback is refused instead of re-applying a known-bad release.
  printf '%s\n' "$PREVIOUS" > "$DEPLOY_DIR/current"

  compose pull || true
  if compose up -d --remove-orphans && wait_healthy; then
    log "rollback complete - now running $PREVIOUS"
    if [ -f "$COMPOSE_DIR/smoke-test.sh" ]; then
      bash "$COMPOSE_DIR/smoke-test.sh" --base-url "${SMOKE_URL:-http://127.0.0.1:${HTTP_PORT}}" \
        && log "rollback smoke tests passed" \
        || err "rollback is up but smoke tests failed - investigate manually"
    fi
    return 0
  fi
  err "rollback also failed - manual intervention required"
  return 1
}

fail_and_maybe_rollback() {
  diagnostics
  err "deployment of $SHA failed"
  rollback || true
  exit 1
}

# --- 5. Deploy ---------------------------------------------------------------
if ! compose pull; then
  err "image pull failed"
  fail_and_maybe_rollback
fi

if ! compose up -d --remove-orphans; then
  fail_and_maybe_rollback
fi

if ! wait_healthy; then
  fail_and_maybe_rollback
fi

# --- 6. Smoke tests (section 18) --------------------------------------------
SMOKE_URL="${SMOKE_URL:-http://127.0.0.1:${HTTP_PORT}}"
if [ -f "$COMPOSE_DIR/smoke-test.sh" ]; then
  if ! bash "$COMPOSE_DIR/smoke-test.sh" --base-url "$SMOKE_URL"; then
    err "smoke tests failed for $SHA"
    fail_and_maybe_rollback
  fi
else
  err "smoke-test.sh not found - refusing to report success"
  fail_and_maybe_rollback
fi

log "DEPLOYMENT OK: $SHA (rollback target: $PREVIOUS)"
log "release metadata:"
log "  $DEPLOY_DIR/current  = $(read_state "$DEPLOY_DIR/current")"
log "  $DEPLOY_DIR/previous = $(read_state "$DEPLOY_DIR/previous")"
