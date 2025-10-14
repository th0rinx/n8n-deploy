#!/usr/bin/env bash
set -euo pipefail
set -x

LOGFILE="/var/log/bootstrap-n8n.log"
SENTINEL_OK="/var/lib/one-context/.provisioned_n8n"
SENTINEL_FAIL="/var/lib/one-context/.provisioned_n8n.failed"
LOCKFILE="/var/run/bootstrap-n8n.lock"

REPO_URL="https://github.com/th0rinx/n8n-deploy.git"
REPO_DIR="/opt/n8n-deploy"
BRANCH_OR_TAG="main"

mkdir -p "$(dirname "$LOGFILE")" /var/lib/one-context /opt /var/run
exec > >(tee -a "$LOGFILE" | logger -t start-script) 2>&1
echo "[start-script] $(date -Is) starting…"

# 1) lock para evitar ejecuciones concurrentes
exec 9>"$LOCKFILE"
flock -n 9 || { echo "[start-script] another instance running, exiting"; exit 0; }

# 2) si ya se provisionó OK, no repitas
[[ -f "$SENTINEL_OK" ]] && { echo "[start-script] already provisioned OK"; exit 0; }

# 3) marca intento (si falla, quedará el .failed)
echo "$(date -Is) RUNNING" > "$SENTINEL_FAIL"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git ca-certificates curl gnupg jq

if [[ -d "$REPO_DIR/.git" ]]; then
  git -C "$REPO_DIR" fetch --all --prune
  git -C "$REPO_DIR" checkout "$BRANCH_OR_TAG"
  git -C "$REPO_DIR" pull --ff-only || true
else
  git clone --depth=1 --branch "$BRANCH_OR_TAG" "$REPO_URL" "$REPO_DIR"
fi

chmod +x "$REPO_DIR/install.sh"
if "$REPO_DIR/install.sh"; then
  echo "$(date -Is) OK" > "$SENTINEL_OK"
  rm -f "$SENTINEL_FAIL"
  echo "[start-script] provisioning completado."
else
  echo "$(date -Is) ERROR" > "$SENTINEL_FAIL"
  echo "[start-script] install.sh failed; see $LOGFILE and /var/log/bootstrap-n8n-install.log"
  exit 1
fi

if command -v onegate >/dev/null 2>&1; then
  onegate vm update --data READY="yes" || true
fi


