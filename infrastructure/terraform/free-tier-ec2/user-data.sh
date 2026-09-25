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
# The deployment scripts require `docker compose` (v2 plugin) and the aws CLI
# for reading SSM Parameter Store. Docker's official repo is used first so the
# compose plugin and buildx are guaranteed; Amazon Linux's own package is the
# fallback if that repo is unreachable.
if [ "${INSTALL_DOCKER:-true}" = "true" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    dnf -y update --security || true
    dnf -y install dnf-plugins-core || true
    dnf config-manager --add-repo https://download.docker.com/linux/amazonlinux/docker-ce.repo || true
    if ! dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin; then
      echo "docker-ce repo unavailable, falling back to the distro docker package"
      dnf -y install docker || true
      dnf -y install docker-compose-plugin docker-buildx-plugin || true
    fi
  fi
  dnf -y install jq || true
  command -v aws >/dev/null 2>&1 || dnf -y install awscli || true

  systemctl enable --now docker
  systemctl enable --now amazon-ssm-agent || true

  if ! docker compose version >/dev/null 2>&1; then
    echo "WARNING: docker compose v2 plugin is not available; deployments will fail"
  fi

  # The ssm-user account is what Session Manager shells run as; give it Docker
  # access so Run Command / interactive sessions can manage containers without
  # exposing SSH.
  id ssm-user >/dev/null 2>&1 && usermod -aG docker ssm-user || true
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
