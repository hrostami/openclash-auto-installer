#!/bin/sh
set -eu

# Legacy compatibility entrypoint.
# The old test downloader was opkg-only and duplicated PassWall download logic.
# Keep this filename working by delegating to the maintained PassWall installer.

REPO="slobys/openclash-auto-installer"
BRANCH="main"
TMP_SCRIPT="/tmp/passwall-installer-test.sh"

log() {
    printf '%s\n' "==> $*"
}

die() {
    printf '%s\n' "[ERROR] $*" >&2
    exit 1
}

if [ -f "./passwall.sh" ]; then
    log "test-auto-download.sh Merged into passwall.sh, transferred to the local passwall.sh"
    exec sh ./passwall.sh "$@"
fi

command -v curl >/dev/null 2>&1 || die "Lack curl command, unable to download passwall.sh"
log "test-auto-download.sh Merged into passwall.sh, download the latest passwall.sh"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/$REPO/$BRANCH/passwall.sh" -o "$TMP_SCRIPT" || die "download passwall.sh fail"
exec sh "$TMP_SCRIPT" "$@"
