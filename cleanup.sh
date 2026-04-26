#!/usr/bin/env bash
set -euo pipefail

# ── Logging helpers ──────────────────────────────────────────────────────────
log_progress() { printf "\r[-] %s" "$1"; }
log_success()  { printf "\r[✓] %s\n" "$1"; }
log_failure()  { printf "\r[x] %s\n" "$1"; }
log_info()     { printf "[i] %s\n"   "$1"; }

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <service-name>"
    echo "  service-name  The slug/name of the deployed Flask service to remove"
    exit 1
}

[[ $# -ne 1 ]] && usage
SLUG="$1"

SERVICE_FILE="/etc/systemd/system/${SLUG}.service"
NGINX_CONF="/etc/nginx/sites-enabled/${SLUG}"
LOG_DIR="/var/log/${SLUG}"

echo "============================================================"
echo "Flask Application Cleanup Script"
echo "============================================================"
echo
log_info "Service : ${SLUG}"
log_info "Service file : ${SERVICE_FILE}"
log_info "Nginx config : ${NGINX_CONF}"
log_info "Log directory: ${LOG_DIR}"
echo

# ── Resolve app directory from service file before we remove it ──────────────
WORK_DIR=""
if [[ -f "$SERVICE_FILE" ]]; then
    WORK_DIR=$(grep -m1 '^WorkingDirectory=' "$SERVICE_FILE" | cut -d= -f2-)
    if [[ -n "$WORK_DIR" ]]; then
        log_info "App directory: ${WORK_DIR}"
    fi
else
    log_info "Service file not found — skipping app directory removal"
fi
echo

# ── Step 1: Stop the service ─────────────────────────────────────────────────
log_progress "Stopping ${SLUG} service"
if sudo systemctl is-active --quiet "${SLUG}" 2>/dev/null; then
    if sudo systemctl stop "${SLUG}" 2>/dev/null; then
        log_success "Stopped ${SLUG} service"
    else
        log_failure "Failed to stop ${SLUG} service"
        exit 1
    fi
else
    log_success "${SLUG} service was not running"
fi

# ── Step 2: Disable the service ──────────────────────────────────────────────
log_progress "Disabling ${SLUG} service"
if sudo systemctl is-enabled --quiet "${SLUG}" 2>/dev/null; then
    if sudo systemctl disable "${SLUG}" 2>/dev/null; then
        log_success "Disabled ${SLUG} service"
    else
        log_failure "Failed to disable ${SLUG} service"
        exit 1
    fi
else
    log_success "${SLUG} service was not enabled"
fi

# ── Step 3: Remove systemd service file ──────────────────────────────────────
log_progress "Removing systemd service file"
if [[ -f "$SERVICE_FILE" ]]; then
    if sudo rm "$SERVICE_FILE"; then
        log_success "Removed ${SERVICE_FILE}"
    else
        log_failure "Failed to remove ${SERVICE_FILE}"
        exit 1
    fi
else
    log_success "Service file not present, nothing to remove"
fi

# ── Step 4: Reload systemd daemon ───────────────────────────────────────────
log_progress "Reloading systemd daemon"
if sudo systemctl daemon-reload; then
    log_success "Systemd daemon reloaded"
else
    log_failure "Failed to reload systemd daemon"
    exit 1
fi

# ── Step 5: Remove Nginx configuration ───────────────────────────────────────
log_progress "Removing Nginx configuration"
if [[ -f "$NGINX_CONF" ]]; then
    if sudo rm "$NGINX_CONF"; then
        log_success "Removed ${NGINX_CONF}"
    else
        log_failure "Failed to remove ${NGINX_CONF}"
        exit 1
    fi
else
    log_success "Nginx config not present, nothing to remove"
fi

# ── Step 6: Test and reload Nginx ────────────────────────────────────────────
log_progress "Testing Nginx configuration"
if sudo nginx -t 2>/dev/null; then
    log_success "Nginx configuration test passed"
else
    log_failure "Nginx configuration test failed — reload skipped"
    exit 1
fi

log_progress "Reloading Nginx"
if sudo systemctl reload nginx; then
    log_success "Nginx reloaded"
else
    log_failure "Failed to reload Nginx"
    exit 1
fi

# ── Step 7: Remove log directory ─────────────────────────────────────────────
log_progress "Removing log directory"
if [[ -d "$LOG_DIR" ]]; then
    if sudo rm -rf "$LOG_DIR"; then
        log_success "Removed ${LOG_DIR}"
    else
        log_failure "Failed to remove ${LOG_DIR}"
        exit 1
    fi
else
    log_success "Log directory not present, nothing to remove"
fi

# ── Step 8: Remove app directory ─────────────────────────────────────────────
if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    log_progress "Removing app directory ${WORK_DIR}"
    if sudo rm -rf "$WORK_DIR"; then
        log_success "Removed ${WORK_DIR}"
    else
        log_failure "Failed to remove ${WORK_DIR}"
        exit 1
    fi
fi

echo
echo "============================================================"
log_success "Cleanup of '${SLUG}' completed successfully!"
echo "============================================================"
echo
