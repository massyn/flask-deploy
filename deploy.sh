#!/usr/bin/env bash
# deploy.sh — self-contained Flask/Gunicorn/Nginx deployment
# Ubuntu/Debian only. Idempotent — safe to re-run against the same slug.
set -eo pipefail

# ============================================================
# Argument parsing
# ============================================================

SLUG=""
DOMAIN=""
REPO=""
PASS=""
CLOUDFLARE=false
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") --slug <slug> --domain <domain> --repo <url> [options]

Required:
  --slug      App identifier (used for all directory and service naming)
  --domain    Nginx server_name value(s), space-separated
  --repo      Git repository URL to clone

Optional:
  --password    Enable HTTP basic auth (username: admin, password: <value>)
  --cloudflare  Block non-Cloudflare traffic using live IP ranges
  --dry-run     Validate the repository only; no server changes

EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --slug)       SLUG="$2";       shift 2 ;;
        --domain)     DOMAIN="$2";     shift 2 ;;
        --repo)       REPO="$2";       shift 2 ;;
        --password)   PASS="$2";       shift 2 ;;
        --cloudflare) CLOUDFLARE=true; shift ;;
        --dry-run)    DRY_RUN=true;    shift ;;
        -h|--help)    usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[[ -z "$SLUG"   ]] && { echo "Error: --slug is required";   usage; }
[[ -z "$DOMAIN" ]] && { echo "Error: --domain is required"; usage; }
[[ -z "$REPO"   ]] && { echo "Error: --repo is required";   usage; }

APP_DIR="/opt/${SLUG}"
DATA_DIR="/data/${SLUG}"
LOG_DIR="/var/log/${SLUG}"
VENV="${APP_DIR}/venv"
SLUG_CONF="/etc/nginx/sites-available/${SLUG}.conf"

# ============================================================
# Dry-run mode — validate repo, no server changes
# ============================================================

if [[ "$DRY_RUN" == "true" ]]; then
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    echo "Cloning ${REPO} for validation..."
    if ! git clone --quiet "$REPO" "$TMP" 2>/dev/null; then
        echo "[✗] Failed to clone repository: ${REPO}"
        exit 1
    fi

    FAIL=false

    if [[ -f "${TMP}/run.py" ]]; then
        echo "[✓] run.py found"
    else
        echo "[✗] run.py missing"
        FAIL=true
    fi

    if [[ -f "${TMP}/requirements.txt" ]]; then
        echo "[✓] requirements.txt found"
    else
        echo "[✗] requirements.txt missing"
        FAIL=true
    fi

    if [[ -f "${TMP}/requirements.txt" ]] && grep -qi "^gunicorn" "${TMP}/requirements.txt"; then
        echo "[✓] gunicorn in requirements.txt"
    else
        echo "[✗] gunicorn not found in requirements.txt"
        FAIL=true
    fi

    if [[ -f "${TMP}/run.py" ]] && grep -qE "(^|\s)app\s*=\s*Flask" "${TMP}/run.py"; then
        echo "[✓] app object found in run.py"
    else
        echo "[✗] app object not found in run.py"
        FAIL=true
    fi

    if [[ ! -f "${TMP}/.env" ]]; then
        echo "[!] .env missing"
    else
        DB=$(grep -i "^DATABASE_URL" "${TMP}/.env" | cut -d= -f2- || true)
        if [[ -n "$DB" && "$DB" != *"/data/${SLUG}/"* ]]; then
            echo "[!] DATABASE_URL not pointing to /data/${SLUG}/ — if your db gets hosed on redeploy, you had fair warning"
        fi
    fi

    if [[ "$FAIL" == "true" ]]; then
        exit 1
    fi

    echo "[✓] All checks passed"
    exit 0
fi

# ============================================================
# Prerequisites
# ============================================================

if ! command -v apt-get &>/dev/null; then
    echo "Error: apt-get not found — Ubuntu/Debian required."
    exit 1
fi

if ! command -v nginx &>/dev/null; then
    echo "Installing nginx..."
    sudo apt-get install -y -q nginx
fi
sudo systemctl enable nginx
sudo systemctl start nginx 2>/dev/null || true

if ! python3 -c "import venv" 2>/dev/null; then
    echo "Installing python3-venv..."
    sudo apt-get install -y -q python3-venv
fi

if [[ -n "$PASS" ]] && ! command -v htpasswd &>/dev/null; then
    echo "Installing apache2-utils..."
    sudo apt-get install -y -q apache2-utils
fi

# ============================================================
# Port assignment
# ============================================================

PORT=""

# Reuse the existing port for this slug if already deployed
if [[ -f "$SLUG_CONF" ]]; then
    PORT=$(grep -oP 'proxy_pass\s+http://127\.0\.0\.1:\K[0-9]+' "$SLUG_CONF" 2>/dev/null | head -1 || true)
fi

# Assign a new port by finding the highest already in use
if [[ -z "$PORT" ]]; then
    HIGHEST=4999
    while IFS= read -r -d '' conf; do
        p=$(grep -oP 'proxy_pass\s+http://127\.0\.0\.1:\K[0-9]+' "$conf" 2>/dev/null | head -1 || true)
        if [[ -n "$p" ]] && (( p > HIGHEST )); then
            HIGHEST=$p
        fi
    done < <(find /etc/nginx/sites-available -name '*.conf' -print0 2>/dev/null)
    PORT=$(( HIGHEST + 1 ))
fi

echo "Port: ${PORT} (internal, localhost only)"

# ============================================================
# Directories
# ============================================================

sudo mkdir -p "$DATA_DIR" "$LOG_DIR"
sudo chown -R www-data:www-data "$DATA_DIR" "$LOG_DIR"

# ============================================================
# Git clone / pull
# ============================================================

if [[ -d "${APP_DIR}/.git" ]]; then
    echo "Pulling latest changes..."
    sudo git -c safe.directory="$APP_DIR" -C "$APP_DIR" fetch --quiet
    sudo git -c safe.directory="$APP_DIR" -C "$APP_DIR" reset --hard FETCH_HEAD
else
    [[ -d "$APP_DIR" ]] && sudo rm -rf "$APP_DIR"
    echo "Cloning repository..."
    sudo git clone --quiet "$REPO" "$APP_DIR"
fi

# ============================================================
# Python venv and dependencies
# ============================================================

if [[ ! -d "$VENV" ]]; then
    sudo python3 -m venv "$VENV"
fi

sudo "${VENV}/bin/pip" install --quiet --upgrade pip
sudo "${VENV}/bin/pip" install --quiet -r "${APP_DIR}/requirements.txt"

# Allow www-data to read and execute the app directory
sudo chown -R www-data:www-data "$APP_DIR"

# ============================================================
# HTTP basic auth
# ============================================================

if [[ -n "$PASS" ]]; then
    sudo mkdir -p /etc/nginx/.htpasswd
    printf '%s' "$PASS" | sudo htpasswd -ci /etc/nginx/.htpasswd/"${SLUG}" admin
fi

# ============================================================
# Cloudflare IP allowlist
# ============================================================

CF_CONF=/etc/nginx/cloudflare-allow.conf

if [[ "$CLOUDFLARE" == "true" ]]; then
    {
        echo "# Cloudflare IPs — generated $(date -u)"
        curl -sf https://www.cloudflare.com/ips-v4 | sed 's/^/allow /; s/$/;/'
        curl -sf https://www.cloudflare.com/ips-v6 | sed 's/^/allow /; s/$/;/'
        echo "deny all;"
    } | sudo tee "$CF_CONF" > /dev/null
    echo "Cloudflare IP allowlist updated."
fi

# ============================================================
# Gunicorn config
# ============================================================

sudo tee "${APP_DIR}/gunicorn_config.py" > /dev/null <<GUNICORN_CFG
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

wsgi_app = "run:app"
bind = "127.0.0.1:${PORT}"
workers = 3
worker_class = "sync"
max_requests = 1000
max_requests_jitter = 50
timeout = 30
keepalive = 2
proc_name = "${SLUG}"
daemon = False
preload_app = True
accesslog = "-"
errorlog = "-"
loglevel = "info"
GUNICORN_CFG

# ============================================================
# Systemd service
# ============================================================

sudo tee "/etc/systemd/system/${SLUG}.service" > /dev/null <<SYSTEMD_UNIT
[Unit]
Description=Gunicorn — ${SLUG}
After=network.target

[Service]
User=www-data
WorkingDirectory=${APP_DIR}
Environment=PATH=${VENV}/bin
ExecStart=${VENV}/bin/gunicorn -c gunicorn_config.py run:app
Restart=always
RestartSec=5
StandardOutput=append:${LOG_DIR}/access.log
StandardError=append:${LOG_DIR}/error.log

[Install]
WantedBy=multi-user.target
SYSTEMD_UNIT

# ============================================================
# Nginx config
# ============================================================

AUTH_DIRECTIVES=""
if [[ -n "$PASS" ]]; then
    AUTH_DIRECTIVES="
        auth_basic \"Restricted\";
        auth_basic_user_file /etc/nginx/.htpasswd/${SLUG};"
fi

CF_DIRECTIVE=""
if [[ "$CLOUDFLARE" == "true" ]]; then
    CF_DIRECTIVE="
        include ${CF_CONF};"
fi

sudo tee "$SLUG_CONF" > /dev/null <<NGINX_CONF
server {
    listen 80;
    server_name ${DOMAIN};

    access_log ${LOG_DIR}/nginx.access.log;
    error_log  ${LOG_DIR}/nginx.error.log;

    location / {${CF_DIRECTIVE}${AUTH_DIRECTIVES}
        proxy_pass         http://127.0.0.1:${PORT};
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
NGINX_CONF

sudo ln -sf "$SLUG_CONF" "/etc/nginx/sites-enabled/${SLUG}.conf"

# ============================================================
# Start services
# ============================================================

sudo systemctl daemon-reload
sudo systemctl enable "${SLUG}.service"
sudo systemctl restart "${SLUG}.service"

if sudo nginx -t 2>/dev/null; then
    sudo systemctl reload nginx
else
    echo "[✗] nginx config test failed:"
    sudo nginx -t
    exit 1
fi

echo ""
echo "================================================="
echo "[✓] Deployment complete"
echo "    Slug   : ${SLUG}"
echo "    Domain : ${DOMAIN}"
echo "    Port   : ${PORT} (internal, localhost only)"
echo "    App    : ${APP_DIR}"
echo "    Data   : ${DATA_DIR}"
echo "    Logs   : ${LOG_DIR}/"
echo "    Status : $(sudo systemctl is-active ${SLUG}.service)"
echo "================================================="
