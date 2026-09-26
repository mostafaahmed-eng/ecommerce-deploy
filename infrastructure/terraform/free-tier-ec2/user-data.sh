#!/bin/bash
# Cloud-init user data for the low-cost Docker Compose demo host.
# Runs once on first boot as root. Every command is idempotent so a forced
# instance replacement re-runs this safely.
set -euo pipefail

exec > >(tee /var/log/ecommerce-userdata.log | logger -t ecommerce-userdata -s 2>/dev/console) 2>&1

echo "=== ecommerce demo host bootstrap started ==="

# --- Directory layout -------------------------------------------------------
# /opt/ecommerce/data              -> durable application state (EBS backed)
# /opt/ecommerce/uploads/receipts  -> durable receipt images (EBS backed)
# /opt/ecommerce/.deployment       -> release metadata (current / previous)
install -d -m 0755 /opt/ecommerce
install -d -m 0755 /opt/ecommerce/data
install -d -m 0750 /opt/ecommerce/uploads
install -d -m 0750 /opt/ecommerce/uploads/receipts
install -d -m 0755 /opt/ecommerce/.deployment
install -d -m 0755 /opt/ecommerce/compose

# --- Packages ---------------------------------------------------------------
# The deployment scripts require `docker compose` (v2 plugin), curl and the aws
# CLI for reading SSM Parameter Store.
#
# Amazon Linux 2023 is used with its own `docker` package. Docker's upstream
# repository is NOT added because it does not exist for Amazon Linux:
#
#   $ curl -o /dev/null -w '%{http_code}' \
#       https://download.docker.com/linux/amazonlinux/docker-ce.repo
#   404
#
# Previously that request was swallowed by `|| true`, so the host silently
# booted with no compose plugin at all, and the resulting problem was downgraded
# to a WARNING that nothing acted on. `scripts/aws/deploy.sh` hard-fails without
# `docker compose`, so the first live deploy died with exit 127. Every failure
# below is therefore fatal: a host that cannot deploy must not look healthy.
if [ "${INSTALL_DOCKER:-true}" = "true" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    dnf -y update --security || true
    dnf -y install docker || { echo "ERROR: unable to install docker"; exit 1; }
  fi
  dnf -y install jq || true
  command -v aws >/dev/null 2>&1 || dnf -y install awscli || { echo "ERROR: unable to install the aws CLI"; exit 1; }
  command -v curl >/dev/null 2>&1 || dnf -y install curl || { echo "ERROR: unable to install curl"; exit 1; }

  systemctl enable --now docker
  systemctl enable --now amazon-ssm-agent || true

  # --- Docker Compose v2 ----------------------------------------------------
  # Not packaged by Amazon Linux 2023 and unavailable from Docker's repo, so the
  # official static binary is installed as a Docker CLI plugin. Verified reachable
  # from the host: HTTP 200, aarch64, ~30 MB.
  if ! docker compose version >/dev/null 2>&1; then
    compose_arch="$(uname -m)"
    compose_url="${COMPOSE_DOWNLOAD_URL:-https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${compose_arch}}"
    plugin_dir="/usr/local/lib/docker/cli-plugins"
    echo "installing docker compose v2 from ${compose_url}"
    install -d -m 0755 "$plugin_dir"
    curl -fsSL --retry 3 --retry-delay 2 -o "$plugin_dir/docker-compose" "$compose_url" \
      || { echo "ERROR: unable to download docker compose for ${compose_arch}"; exit 1; }
    chmod 0755 "$plugin_dir/docker-compose"
  fi
  docker compose version || { echo "ERROR: docker compose v2 is required but is not usable"; exit 1; }

  # The ssm-user account is what Session Manager shells run as; give it Docker
  # access so Run Command / interactive sessions can manage containers without
  # exposing SSH.
  id ssm-user >/dev/null 2>&1 && usermod -aG docker ssm-user || true
fi

# --- Host-side deployment entry point ---------------------------------------
# The deploy job runs `bash /opt/ecommerce/compose/deploy.sh --sha <SHA> ...`,
# but nothing else put that file on the host - this directory was created empty
# above, which is why the first live deploy failed with:
#
#   bash: /opt/ecommerce/compose/deploy.sh: No such file or directory
#
# The launcher is fetched at boot so the host is usable on its own. It is
# deliberately unpinned: `deploy.sh` downloads every configuration file itself
# at the exact SHA it is asked to deploy, and the GitHub Actions job re-stages
# the launcher from that SHA before running it (so the file executed is always
# the pinned one, never a stale copy).
if [ "${INSTALL_DEPLOY_SCRIPT:-true}" = "true" ]; then
  deploy_repo="${DEPLOY_SCRIPT_REPO:-mostafaahmed-eng/ecommerce-deploy}"
  deploy_ref="${DEPLOY_SCRIPT_REF:-main}"
  deploy_url="https://raw.githubusercontent.com/${deploy_repo}/${deploy_ref}/scripts/aws/deploy.sh"
  echo "staging deployment entry point from ${deploy_url}"
  curl -fsSL --retry 3 -o /tmp/deploy.sh "$deploy_url" \
    || { echo "ERROR: unable to download deploy.sh from ${deploy_repo}@${deploy_ref}"; exit 1; }
  install -d -m 0755 /opt/ecommerce/compose
  install -m 0755 /tmp/deploy.sh /opt/ecommerce/compose/deploy.sh
  rm -f /tmp/deploy.sh
  bash /opt/ecommerce/compose/deploy.sh --help >/dev/null 2>&1 \
    || { echo "ERROR: /opt/ecommerce/compose/deploy.sh is not usable"; exit 1; }
  echo "staged /opt/ecommerce/compose/deploy.sh"
fi

# --- Shell quality of life --------------------------------------------------
cat >/etc/profile.d/ecommerce.sh <<'PROFILE'
export ECOMMERCE_HOME=/opt/ecommerce
alias ec-status='docker compose -f /opt/ecommerce/compose/docker-compose.prod.yml ps'
alias ec-logs='docker compose -f /opt/ecommerce/compose/docker-compose.prod.yml logs --tail=200'
PROFILE
chmod 0644 /etc/profile.d/ecommerce.sh

# --- Small but useful dashboard for the demo --------------------------------
cat >/usr/local/bin/ecommerce-health <<'HEALTH'
#!/bin/bash
set -euo pipefail
echo "--- containers ---"
docker compose -f /opt/ecommerce/compose/docker-compose.prod.yml ps || true
echo "--- release ---"
cat /opt/ecommerce/.deployment/current 2>/dev/null || echo "no deployment recorded"
echo "--- local smoke ---"
curl -fsS -o /dev/null -w "GET /           -> %{http_code}\n" http://127.0.0.1/ || true
curl -fsS -o /dev/null -w "GET /api/health -> %{http_code}\n" http://127.0.0.1/api/health || true
curl -fsS -o /dev/null -w "GET /api/products -> %{http_code}\n" http://127.0.0.1/api/products || true
HEALTH
chmod 0755 /usr/local/bin/ecommerce-health

echo "=== ecommerce demo host bootstrap completed ==="
