#!/usr/bin/env bash
# build_server.sh — install prerequisites, configure AWS credentials, and set up backup/heartbeat cron jobs
# Ubuntu/Debian only. Idempotent — safe to re-run.
set -eo pipefail

ENV_DIR="/etc/flask-deploy"
ENV_FILE="${ENV_DIR}/.env"

# ============================================================
# Load existing env
# ============================================================

if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

# ============================================================
# Prompt for missing variables
# ============================================================

prompt_if_unset() {
    local var_name="$1"
    local prompt_text="$2"
    local secret="${3:-false}"

    if [[ -z "${!var_name:-}" ]]; then
        if [[ "$secret" == "true" ]]; then
            read -rsp "${prompt_text}: " value
            echo
        else
            read -rp "${prompt_text}: " value
        fi
        printf -v "$var_name" '%s' "$value"
        export "$var_name"
    fi
}

prompt_if_unset AWS_ACCESS_KEY_ID     "AWS_ACCESS_KEY_ID"     true
prompt_if_unset AWS_SECRET_ACCESS_KEY "AWS_SECRET_ACCESS_KEY" true
prompt_if_unset AWS_REGION            "AWS_REGION"
prompt_if_unset AWS_S3_BUCKET         "AWS_S3_BUCKET"
prompt_if_unset HC_HEARTBEAT          "HC_HEARTBEAT URL"
prompt_if_unset HC_BACKUP             "HC_BACKUP URL"

# ============================================================
# Write env file
# ============================================================

sudo mkdir -p "$ENV_DIR"
sudo tee "$ENV_FILE" > /dev/null <<EOF
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION}
AWS_S3_BUCKET=${AWS_S3_BUCKET}
HC_HEARTBEAT=${HC_HEARTBEAT}
HC_BACKUP=${HC_BACKUP}
EOF
sudo chmod 600 "$ENV_FILE"

# ============================================================
# System update and prerequisites
# ============================================================

sudo apt-get update -q
sudo apt-get upgrade -y -q
sudo apt-get install -y -q unzip curl

if ! command -v aws &>/dev/null; then
    echo "Installing AWS CLI..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2
    sudo /tmp/awscliv2/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/awscliv2
fi

# ============================================================
# Configure AWS CLI
# ============================================================

aws configure set aws_access_key_id     "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set region                "$AWS_REGION"

# ============================================================
# Helper scripts (always replaced)
# ============================================================

sudo tee /usr/local/bin/backup.sh > /dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -eo pipefail
set -a
source /etc/flask-deploy/.env
set +a
/usr/local/bin/aws s3 cp /data "s3://${AWS_S3_BUCKET}/$(date +%Y/%m/%d)" --recursive --no-progress
/usr/bin/curl -fsS "${HC_BACKUP}" > /dev/null
SCRIPT
sudo chmod +x /usr/local/bin/backup.sh

sudo tee /usr/local/bin/heartbeat.sh > /dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -a
source /etc/flask-deploy/.env
set +a
/usr/bin/curl -fsS "${HC_HEARTBEAT}" > /dev/null
SCRIPT
sudo chmod +x /usr/local/bin/heartbeat.sh

# ============================================================
# Cron jobs
# ============================================================

CRON_TMP=$(mktemp)
crontab -l 2>/dev/null > "$CRON_TMP" || true

if ! grep -qF "backup.sh" "$CRON_TMP"; then
    echo "0 2 * * * /usr/local/bin/backup.sh > /tmp/backup.log 2>&1" >> "$CRON_TMP"
fi

if ! grep -qF "heartbeat.sh" "$CRON_TMP"; then
    echo "* * * * * /usr/local/bin/heartbeat.sh > /dev/null 2>&1" >> "$CRON_TMP"
fi

crontab "$CRON_TMP"
rm -f "$CRON_TMP"

# ============================================================
# Done
# ============================================================

echo ""
echo "================================================="
echo "[✓] Build server setup complete"
echo "    Env      : ${ENV_FILE}"
echo "    AWS CLI  : $(aws --version 2>&1 | head -1)"
echo "    Backup   : daily at 02:00 → s3://${AWS_S3_BUCKET}/<YYYY/MM/DD>/"
echo "    Heartbeat: every minute   → ${HC_HEARTBEAT}"
echo "================================================="
