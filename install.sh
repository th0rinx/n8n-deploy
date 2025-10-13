#!/usr/bin/env bash
set -euo pipefail

# Log a archivo (si se ejecuta fuera del start script)
LOGFILE="/var/log/bootstrap-n8n-install.log"
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1

log(){ echo "[n8n-setup] $*"; }

ENV_FILE="/etc/n8n/n8n.env"
export DEBIAN_FRONTEND=noninteractive

# --- Paquetes base ---
apt-get update -y
apt-get install -y ca-certificates curl gnupg jq

# --- Node.js 22 ---
if ! command -v node >/dev/null 2>&1; then
  log "Instalando Node.js 22 (NodeSource)"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
log "node: $(node -v)  npm: $(npm -v)"

# --- n8n ---
if ! command -v n8n >/dev/null 2>&1; then
  log "Instalando n8n (npm -g)"
  npm i -g n8n
fi
N8N_BIN="$(command -v n8n)"
log "n8n: $N8N_BIN"

# --- usuario/dirs ---
id n8n >/dev/null 2>&1 || useradd -r -m -d /var/lib/n8n -s /usr/sbin/nologin n8n
mkdir -p /var/lib/n8n /var/log/n8n /etc/n8n
chown -R n8n:n8n /var/lib/n8n /var/log/n8n /etc/n8n

# --- .env ---
if [[ ! -f "$ENV_FILE" ]]; then
cat >"$ENV_FILE" <<'EOF'
N8N_USER_FOLDER=/var/lib/n8n
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_DIAGNOSTICS_ENABLED=false
N8N_PERSONALIZATION_ENABLED=false
DB_TYPE=sqlite
DB_SQLITE_POOL_SIZE=5
N8N_RUNNERS_ENABLED=true
N8N_BLOCK_ENV_ACCESS_IN_NODE=true
N8N_GIT_NODE_DISABLE_BARE_REPOS=true
N8N_SECURE_COOKIE=false
EOF
fi
grep -q '^N8N_ENCRYPTION_KEY=' "$ENV_FILE" || echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)" >> "$ENV_FILE"
chown n8n:n8n "$ENV_FILE" || true

# --- systemd unit ---
if ! systemctl cat n8n >/dev/null 2>&1; then
  cat >/etc/systemd/system/n8n.service <<EOF
[Unit]
Description=n8n (Node.js)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=n8n
Group=n8n
EnvironmentFile=/etc/n8n/n8n.env
WorkingDirectory=/var/lib/n8n
ExecStart=${N8N_BIN}
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable n8n
fi

# --- start ---
systemctl restart n8n || systemctl start n8n
log "OK: n8n escuchando en http://<IP>:5678"
