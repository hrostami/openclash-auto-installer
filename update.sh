#!/bin/sh
set -eu

SCRIPT_URL="https://raw.githubusercontent.com/slobys/openclash-auto-installer/main/install.sh"
TMP_FILE="/tmp/openclash-auto-update.sh"

log() {
    printf '%s\n' "==> $*"
}

die() {
    printf '%s\n' "[ERROR] $*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "Lack curl Order"

log "Download the latest installation/update script"
curl -fsSL --retry 3 "$SCRIPT_URL" -o "$TMP_FILE" || die "Failed to download remote script"
chmod +x "$TMP_FILE"

if [ "${1:-}" = "--check" ] || [ "${1:-}" = "--check-update" ]; then
    log "Start checking for new versions"
    sh "$TMP_FILE" --check-update --skip-pkg-update
else
    log "Start performing update"
    sh "$TMP_FILE" --skip-pkg-update "$@"
fi
