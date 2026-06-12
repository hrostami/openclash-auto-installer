#!/bin/sh
set -eu

# Legacy compatibility entrypoint.
# The old implementation was a hard-coded OpenWrt 24.10/aarch64/opkg PassWall helper.
# Keep this filename working by delegating to the maintained PassWall installer,
# which now supports both opkg and OpenWrt 25.12+ apk environments.

REPO="hrostami/openclash-auto-installer"
BRANCH="main"
TMP_SCRIPT="/tmp/passwall-installer.sh"

log() {
    printf '%s\n' "==> $*"
}

die() {
    printf '%s\n' "[ERROR] $*" >&2
    exit 1
}

if [ -f "./passwall.sh" ]; then
    log "auto-download-pro.sh Merged into passwall.sh, transferred to the local passwall.sh"
    exec sh ./passwall.sh "$@"
fi

command -v curl >/dev/null 2>&1 || die "Lack curl command, unable to download passwall.sh"
log "auto-download-pro.sh Merged into passwall.sh, download the latest passwall.sh"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/$REPO/$BRANCH/passwall.sh" -o "$TMP_SCRIPT" || die "download passwall.sh fail"
exec sh "$TMP_SCRIPT" "$@"
