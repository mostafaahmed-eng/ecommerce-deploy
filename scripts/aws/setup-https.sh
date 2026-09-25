#!/usr/bin/env bash
#
# Second-stage HTTPS enablement for the low-cost EC2 profile.
#
#   scripts/aws/setup-https.sh example.com admin@example.com [--staging] [--force]
#
# The site is fully usable over plain HTTP before this script is ever run; this
# only ADDS TLS. If anything fails, the HTTP server in conf.d/00-default.conf is
# left untouched, so a broken certificate attempt can never take the site down.
#
# What it does:
#   1. validates the domain / email arguments
#   2. compares DNS with this instance's public IP (warning only, --skip-dns to ignore)
#   3. issues a Let's Encrypt certificate using the HTTP-01 webroot challenge
#   4. renders nginx/https.conf.tpl into conf.d/443-ssl.conf
#   5. runs `nginx -t` and only reloads when the configuration is valid
#   6. installs a twice-daily renewal job that reloads nginx only when the
#      certificate actually changed
#
# Production owner authentication uses Secure cookies, so the owner dashboard
# only becomes fully functional after this script succeeds.
#
set -euo pipefail

ROOT="${ECOMMERCE_HOME:-/opt/ecommerce}"
COMPOSE_DIR="$ROOT/compose"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.prod.yml"
COMPOSE_DOTENV="$COMPOSE_DIR/.env"
LETSENCRYPT_DIR="$ROOT/letsencrypt"
CERTBOT_WWW="$ROOT/certbot-www"
CERTBOT_IMAGE="${CERTBOT_IMAGE:-certbot/certbot}"
DOMAIN=""
EMAIL=""
STAGING=0
FORCE=0
SKIP_DNS=0

log() { printf '[https] %s\n' "$*"; }
err() { printf '[https] ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --staging)  STAGING=1 ;;
    --force)    FORCE=1 ;;
    --skip-dns) SKIP_DNS=1 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die "unknown option: $1" ;;
    *)
      if [ -z "$DOMAIN" ]; then DOMAIN="$1"
      elif [ -z "$EMAIL" ]; then EMAIL="$1"
      else die "unexpected argument: $1"; fi
      ;;
  esac
  shift
done

# --- 1. Argument validation ---------------------------------------------------
[ -n "$DOMAIN" ] && [ -n "$EMAIL" ] || { err "usage: setup-https.sh <domain> <email>"; usage; exit 2; }

echo "$DOMAIN" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' \
  || die "'$DOMAIN' is not a valid fully-qualified domain name"
echo "$EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' \
  || die "'$EMAIL' is not a valid email address"

command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "the docker compose v2 plugin is required"
[ -f "$COMPOSE_FILE" ] || die "$COMPOSE_FILE not found - deploy first"

mkdir -p "$LETSENCRYPT_DIR" "$CERTBOT_WWW"

NGINX_CONF_DIR="$COMPOSE_DIR/nginx"
TEMPLATE="$NGINX_CONF_DIR/https.conf.tpl"
RENDERED="$NGINX_CONF_DIR/conf.d/443-ssl.conf"
[ -f "$TEMPLATE" ] || die "missing template $TEMPLATE"

if [ -f "$RENDERED" ] && [ "$FORCE" -eq 0 ]; then
  log "TLS is already configured ($RENDERED exists). Use --force to reissue."
  exit 0
fi

# --- 2. DNS sanity check (advisory) ------------------------------------------
resolve_ipv4() {
  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$1" 2>/dev/null | awk '{print $1; exit}'
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$1" 2>/dev/null | awk '/^Address: /{print $2; exit}'
  fi
}

instance_public_ip() {
  local token
  token="$(curl -fsS -m 3 -X PUT 'http://169.254.169.254/latest/api/token' \
             -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' 2>/dev/null || true)"
  if [ -n "$token" ]; then
    curl -fsS -m 3 -H "X-aws-ec2-metadata-token: $token" \
         'http://169.254.169.254/latest/meta-data/public-ipv4' 2>/dev/null || true
  fi
}

if [ "$SKIP_DNS" -eq 0 ]; then
  DNS_IP="$(resolve_ipv4 "$DOMAIN" || true)"
  OWN_IP="$(instance_public_ip || true)"
  if [ -z "$DNS_IP" ]; then
    log "WARNING: $DOMAIN does not resolve yet. HTTP-01 issuance will fail until DNS propagates."
    log "         Re-run this script once the A record points at $OWN_IP."
  elif [ -n "$OWN_IP" ] && [ "$DNS_IP" != "$OWN_IP" ]; then
    log "WARNING: $DOMAIN resolves to $DNS_IP but this instance is $OWN_IP."
    log "         Certificate issuance will fail while they differ (use --skip-dns to ignore)."
  else
    log "DNS OK: $DOMAIN -> ${DNS_IP}${OWN_IP:+ (matches this instance)}"
  fi
fi

# --- 3. Issue the certificate -------------------------------------------------
# HTTP-01 through the nginx webroot: no ports other than 80 are needed and the
# application containers are not involved at all.
log "requesting certificate for $DOMAIN (email: $EMAIL)$([ "$STAGING" -eq 1 ] && echo ' [LETSENCRYPT-STAGING]' || true)"
CERTBOT_ARGS=(certonly --webroot -w /var/www/certbot
              --domain "$DOMAIN" --email "$EMAIL"
              --agree-tos --non-interactive --keep-until-expiring)
[ "$STAGING" -eq 1 ] && CERTBOT_ARGS+=(--staging)
[ "$FORCE" -eq 1 ]   && CERTBOT_ARGS+=(--force-renewal)

if ! docker run --rm \
    -v "$LETSENCRYPT_DIR:/etc/letsencrypt" \
    -v "$CERTBOT_WWW:/var/www/certbot" \
    "$CERTBOT_IMAGE" "${CERTBOT_ARGS[@]}"; then
  die "certificate issuance failed. Check that $DOMAIN's A record points at this instance, then re-run."
fi

FULLCHAIN="$LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem"
PRIVKEY="$LETSENCRYPT_DIR/live/$DOMAIN/privkey.pem"
[ -f "$FULLCHAIN" ] && [ -f "$PRIVKEY" ] || die "certificate files not found under $LETSENCRYPT_DIR/live/$DOMAIN"

# --- 4. Render the HTTPS server block ----------------------------------------
sed -e "s|__SERVER_NAME__|$DOMAIN|g" \
    -e "s|__CERT_FULLCHAIN__|/etc/letsencrypt/live/$DOMAIN/fullchain.pem|g" \
    -e "s|__CERT_KEY__|/etc/letsencrypt/live/$DOMAIN/privkey.pem|g" \
    "$TEMPLATE" > "$RENDERED"
chmod 644 "$RENDERED"
log "wrote $RENDERED"

# --- 5. Validate before reloading (never break a running site) ---------------
compose() { docker compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_DOTENV" "$@"; }

reload_or_revert() {
  if compose exec -T nginx nginx -t; then
    compose exec -T nginx nginx -s reload
    log "nginx reloaded with TLS enabled -> https://$DOMAIN/"
    return 0
  fi
  err "nginx rejected the new configuration - reverting to HTTP only"
  rm -f "$RENDERED"
  compose exec -T nginx nginx -t && compose exec -T nginx nginx -s reload
  die "TLS configuration rolled back; the site is still serving over HTTP"
}
reload_or_revert

# --- 6. Renewal job -----------------------------------------------------------
# Renewals use the same webroot, so they keep working even if the app is down.
# nginx is only reloaded when a certificate actually changed.
RENEW_SCRIPT="$COMPOSE_DIR/renew-https.sh"
cat > "$RENEW_SCRIPT" <<RENEW
#!/usr/bin/env bash
# Generated by setup-https.sh - renews $DOMAIN and reloads nginx only on change.
set -euo pipefail
ROOT="$ROOT"
COMPOSE_FILE="$COMPOSE_FILE"
COMPOSE_DOTENV="$COMPOSE_DOTENV"
CERTBOT_WWW="$CERTBOT_WWW"
LETSENCRYPT_DIR="$LETSENCRYPT_DIR"
CERTBOT_IMAGE="$CERTBOT_IMAGE"

stamp_before="\$(date -r "\$LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem" +%s 2>/dev/null || echo 0)"

docker run --rm \\
  -v "\$LETSENCRYPT_DIR:/etc/letsencrypt" \\
  -v "\$CERTBOT_WWW:/var/www/certbot" \\
  "\$CERTBOT_IMAGE" renew --webroot -w /var/www/certbot --quiet

stamp_after="\$(date -r "\$LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem" +%s 2>/dev/null || echo 0)"
if [ "\$stamp_before" != "\$stamp_after" ]; then
  echo "[renew] certificate changed - reloading nginx"
  docker compose -f "\$COMPOSE_FILE" --env-file "\$COMPOSE_DOTENV" exec -T nginx nginx -t \\
    && docker compose -f "\$COMPOSE_FILE" --env-file "\$COMPOSE_DOTENV" exec -T nginx nginx -s reload
else
  echo "[renew] certificate unchanged - no reload needed"
fi
RENEW
chmod 755 "$RENEW_SCRIPT"

if command -v crontab >/dev/null 2>&1; then
  EXISTING="$(crontab -l 2>/dev/null | grep -c "$RENEW_SCRIPT" || true)"
  if [ "$EXISTING" -eq 0 ]; then
    (crontab -l 2>/dev/null | grep -v "$RENEW_SCRIPT"; echo "17 3,15 * * * $RENEW_SCRIPT >> $ROOT/https-renew.log 2>&1") | crontab -
    log "installed renewal cron: 03:17 and 15:17 daily -> $ROOT/https-renew.log"
  else
    log "renewal cron already installed"
  fi
elif [ -d /etc/cron.d ]; then
  printf '17 3,15 * * * root %s >> %s/https-renew.log 2>&1\n' "$RENEW_SCRIPT" "$ROOT" > /etc/cron.d/ecommerce-https
  chmod 644 /etc/cron.d/ecommerce-https
  log "installed /etc/cron.d/ecommerce-https (03:17 and 15:17 daily)"
else
  log "WARNING: no cron available. Schedule $RENEW_SCRIPT manually twice a day."
fi

log "DONE. Verify with: curl -I https://$DOMAIN/"
log "The owner dashboard now receives Secure cookies and is fully usable over HTTPS."
