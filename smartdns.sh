#!/bin/sh
set -eu

LOCKDIR="/tmp/smartdns-install.lock"
TMP_ROOT="/tmp/smartdns-install"
SMARTDNS_API="https://api.github.com/repos/pymumu/smartdns/releases/latest"
RESTART_SERVICES="1"
FORCE_PKG_UPDATE="1"

cleanup() {
    rm -rf "$TMP_ROOT"
    rmdir "$LOCKDIR" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

log() {
    printf '%s\n' "==> $*"
}

warn() {
    printf '%s\n' "[WARN] $*" >&2
}

die() {
    printf '%s\n' "[ERROR] $*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

usage() {
    cat <<'EOF_USAGE'
usage:
  sh smartdns.sh [Options]

Options:
  --skip-restart      Don't try to enable when done / Restart smartdns
  --skip-pkg-update   jump over opkg update / apk update
  -h, --help          show help
EOF_USAGE
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --skip-restart)
                RESTART_SERVICES="0"
                ;;
            --skip-pkg-update)
                FORCE_PKG_UPDATE="0"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown parameters: $1"
                ;;
        esac
        shift
    done
}

detect_pkg_mgr() {
    if command -v opkg >/dev/null 2>&1; then
        printf 'opkg'
    elif command -v apk >/dev/null 2>&1; then
        printf 'apk'
    else
        die "not detected opkg or apk, the current system does not support it yet"
    fi
}

get_distr_arch() {
    if [ -f /etc/openwrt_release ]; then
        # shellcheck disable=SC1091
        . /etc/openwrt_release >/dev/null 2>&1 || true
        printf '%s' "${DISTRIB_ARCH:-}"
    else
        printf ''
    fi
}

detect_smartdns_arch() {
    RAW_ARCH="$(uname -m 2>/dev/null || true)"
    DIST_ARCH="$(get_distr_arch)"
    MATCH_STR="$RAW_ARCH $DIST_ARCH"

    case "$MATCH_STR" in
        *x86_64*|*amd64*)
            printf 'x86_64'
            ;;
        *i386*|*i686*|*x86*)
            printf 'x86'
            ;;
        *aarch64*|*arm64*|*armv8*)
            printf 'aarch64'
            ;;
        *arm*)
            printf 'arm'
            ;;
        *mipsel*)
            printf 'mipsel'
            ;;
        *mips*)
            printf 'mips'
            ;;
        *)
            printf ''
            ;;
    esac
}

download_url() {
    URL="$1"
    OUT="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 15 \
            -A "openclaw-openwrt-installer" \
            "$URL" -o "$OUT"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$OUT" --user-agent="openclaw-openwrt-installer" "$URL"
    else
        die "Lack curl or wget, unable to download file"
    fi
}

download_github_api() {
    URL="$1"
    OUT="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 15 \
            -A "openclaw-openwrt-installer" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$URL" -o "$OUT"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$OUT" \
            --user-agent="openclaw-openwrt-installer" \
            --header="Accept: application/vnd.github+json" \
            --header="X-GitHub-Api-Version: 2022-11-28" \
            "$URL"
    else
        die "Lack curl or wget, unable to download file"
    fi
}

fetch_release_json() {
    if download_github_api "$SMARTDNS_API" "$TMP_ROOT/release.json"; then
        return 0
    fi

    warn "GitHub API Failed to get, try to get from Release Page parsing download list"
    download_url "https://github.com/pymumu/smartdns/releases/latest" "$TMP_ROOT/latest.html" || die "Get SmartDNS up to date Release Page failed"

    LATEST_TAG="$(sed -n 's#.*releases/tag/\(Release[^"?<> ]*\).*#\1#p' "$TMP_ROOT/latest.html" | head -n1 || true)"
    [ -n "$LATEST_TAG" ] || die "Unable to parse SmartDNS up to date Release Label"

    download_url "https://github.com/pymumu/smartdns/releases/expanded_assets/$LATEST_TAG" "$TMP_ROOT/assets.html" || die "Get SmartDNS Release Asset list failed"
    sed -n 's#.*href="\(/pymumu/smartdns/releases/download/[^"?]*\)".*#{"browser_download_url":"https://github.com\1"}#p' "$TMP_ROOT/assets.html" > "$TMP_ROOT/release.json"
    [ -s "$TMP_ROOT/release.json" ] || die "Unable to parse SmartDNS Release Asset download link"
}

find_asset_url() {
    PATTERN="$1"
    sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP_ROOT/release.json" | grep "$PATTERN" | head -n1 || true
}

get_installed_version() {
    PKG_MGR="$1"
    case "$PKG_MGR" in
        opkg)
            opkg status smartdns 2>/dev/null | sed -n 's/^Version: //p' | head -n1 || true
            ;;
        apk)
            apk info -a smartdns 2>/dev/null | sed -n 's/^version: //p' | head -n1 || true
            ;;
    esac
}

maybe_update_index() {
    PKG_MGR="$1"
    if [ "$FORCE_PKG_UPDATE" != "1" ]; then
        log "Skip software source updates by parameter"
        return 0
    fi

    case "$PKG_MGR" in
        opkg)
            log "refresh opkg Software source index"
            opkg update || warn "opkg update Failure, will continue to try to install GitHub Release Bag"
            ;;
        apk)
            log "refresh apk Software source index"
            apk update || warn "apk update Failure, will continue to try to install GitHub Release Bag"
            ;;
    esac
}

install_release_packages() {
    PKG_MGR="$1"
    SMARTDNS_ARCH="$2"

    case "$PKG_MGR" in
        opkg)
            EXT="ipk"
            INSTALL_CMD="opkg install"
            ;;
        apk)
            EXT="apk"
            INSTALL_CMD="apk add --allow-untrusted"
            ;;
    esac

    CORE_URL="$(find_asset_url "smartdns\..*\.${SMARTDNS_ARCH}-openwrt-all\.${EXT}$")"
    LUCI_URL="$(find_asset_url "luci-app-smartdns\..*\.all-luci-all\.${EXT}$")"

    [ -n "$CORE_URL" ] || die "Not found for current architecture SmartDNS Release Bag: $SMARTDNS_ARCH / $EXT"
    [ -n "$LUCI_URL" ] || die "not found LuCI SmartDNS Release Bag: $EXT"

    CORE_PKG="$TMP_ROOT/$(basename "$CORE_URL")"
    LUCI_PKG="$TMP_ROOT/$(basename "$LUCI_URL")"

    log "download SmartDNS: $(basename "$CORE_PKG")"
    download_url "$CORE_URL" "$CORE_PKG" || die "download SmartDNS Package failed"

    log "download LuCI SmartDNS: $(basename "$LUCI_PKG")"
    download_url "$LUCI_URL" "$LUCI_PKG" || die "download LuCI SmartDNS Package failed"

    log "Install / renew SmartDNS"
    # shellcheck disable=SC2086
    $INSTALL_CMD "$CORE_PKG" || die "Install SmartDNS Failed, please check system dependencies or software sources"

    if [ "$PKG_MGR" = "opkg" ] && opkg status luci-i18n-smartdns-zh-cn >/dev/null 2>&1; then
        warn "Old version detected luci-i18n-smartdns-zh-cn Possibly with new version luci-app-smartdns File conflicts, use --force-depends pre-remove"
        opkg remove --force-depends luci-i18n-smartdns-zh-cn || die "Failed to remove conflicting language pack, please do it manually: opkg remove --force-depends luci-i18n-smartdns-zh-cn"
    fi

    log "Install / renew LuCI SmartDNS interface"
    # shellcheck disable=SC2086
    $INSTALL_CMD "$LUCI_PKG" || die "Install LuCI SmartDNS Failed, please check system dependencies or software sources"
}

refresh_luci() {
    rm -rf /tmp/luci-* /tmp/.luci* /tmp/etc/config/ucitrack /var/run/luci-indexcache 2>/dev/null || true
    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd restart >/dev/null 2>&1 || warn "rpcd Restart failed"
    fi
}

restart_smartdns() {
    if [ "$RESTART_SERVICES" != "1" ]; then
        log "Skip by parameter smartdns enable / Restart"
        return 0
    fi

    if [ -x /etc/init.d/smartdns ]; then
        /etc/init.d/smartdns enable >/dev/null 2>&1 || warn "smartdns enable fail"
        /etc/init.d/smartdns restart >/dev/null 2>&1 || warn "smartdns restart fail"
    else
        warn "not found /etc/init.d/smartdns, skip service restart"
    fi
}

main() {
    parse_args "$@"

    if ! mkdir "$LOCKDIR" 2>/dev/null; then
        die "There is already another SmartDNS Task is running"
    fi
    mkdir -p "$TMP_ROOT"

    need_cmd sed
    need_cmd grep
    need_cmd head
    need_cmd basename

    PKG_MGR="$(detect_pkg_mgr)"
    SMARTDNS_ARCH="$(detect_smartdns_arch)"
    [ -n "$SMARTDNS_ARCH" ] || die "The current architecture is not supported yet: $(uname -m 2>/dev/null || printf unknown)"

    log "Package manager detected: $PKG_MGR"
    log "detected SmartDNS Architecture: $SMARTDNS_ARCH"
    OLD_VER="$(get_installed_version "$PKG_MGR")"
    log "Currently installed version: ${OLD_VER:-not installed}"

    maybe_update_index "$PKG_MGR"
    fetch_release_json
    install_release_packages "$PKG_MGR" "$SMARTDNS_ARCH"
    restart_smartdns
    refresh_luci

    NEW_VER="$(get_installed_version "$PKG_MGR")"
    log "Post-installation version: ${NEW_VER:-unknown}"
    warn "Not actively rewritten by default /etc/config/smartdns;please LuCI Click on your network environment to enable or adjust DNS Forwarding settings"
    warn "if LuCI The menu does not appear immediately, please refresh the page or log in again LuCI"
    log "SmartDNS Processing completed"
}

main "$@"
