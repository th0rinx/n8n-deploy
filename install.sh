#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/bootstrap-n8n.log"
SENTINEL="/var/lib/one-context/.provisioned_n8n"

REPO_URL="https://github.com/th0rinx/n8n-deploy.git"
REPO_DIR="/opt/n8n-deploy"        # <— carpeta donde clonamos el repo
BRANCH_OR_TAG="main"              # o un tag, p.ej. v1.0.0

# ==== logging a archivo + consola ====
mkdir -p "$(dirname "$LOGFILE")" /var/lib/one-context
exec > >(tee -a "$LOGFILE") 2>&1
echo "[start-script] $(date -Is) starting…"

# ==== idempotencia ====
if [[ -f "$SENTINEL" ]]; then
  echo "[start-script] sentinel presente; nada que hacer."
  exit 0
fi

# ==== prereqs ====
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git ca-certificates curl gnupg jq

# ==== clonar o actualizar repo ====
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "[start-script] repo existe, actualizando…"
  git -C "$REPO_DIR" fetch --all --prune
  git -C "$REPO_DIR" checkout "$BRANCH_OR_TAG"
  git -C "$REPO_DIR" pull --ff-only || true
else
  echo "[start-script] clonando repo…"
  git clone --depth=1 --branch "$BRANCH_OR_TAG" "$REPO_URL" "$REPO_DIR"
fi

# ==== ejecutar instalador ====
chmod +x "$REPO_DIR/install.sh"
"$REPO_DIR/install.sh"

# ==== marcar como completado ====
echo "$(date -Is) OK" > "$SENTINEL"
echo "[start-script] provisioning completado."

