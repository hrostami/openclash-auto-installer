#!/bin/sh
set -eu

LOCKDIR="/tmp/mosdns-install.lock"
TMP_ROOT="/tmp/mosdns-install"
MOSDNS_REPO="sbwml/luci-app-mosdns"
MOSDNS_API="https://api.github.com/repos/$MOSDNS_REPO/releases/latest"
MOSDNS_RELEASE_URL="https://github.com/$MOSDNS_REPO/releases/latest"
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
  sh mosdns.sh [Options]

Options:
  --skip-restart      Don't try to enable when done / Restart mosdns
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

select_sdk() {
    PKG_MGR="$1"
    case "$PKG_MGR" in
        apk)
            printf 'openwrt-25.12'
            ;;
        opkg)
            printf 'openwrt-24.10'
            ;;
        *)
            die "Unknown package manager: $PKG_MGR"
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

find_asset_url() {
    ASSET_NAME="$1"

    if [ -f "$TMP_ROOT/release.json" ]; then
        JSON_URL="$(sed 's/"browser_download_url"/\
"browser_download_url"/g' "$TMP_ROOT/release.json" |
            sed -n 's/^"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
            grep "/$ASSET_NAME$" |
            head -n1 || true)"
        if [ -n "$JSON_URL" ]; then
            printf '%s\n' "$JSON_URL"
            return 0
        fi
    fi

    for html in "$TMP_ROOT/release-assets.html" "$TMP_ROOT/release.html"; do
        [ -f "$html" ] || continue
        HTML_URL="$(grep -o "/$MOSDNS_REPO/releases/download/[^\"'<> ]*/$ASSET_NAME" "$html" | head -n1 || true)"
        [ -n "$HTML_URL" ] && printf 'https://github.com%s\n' "$HTML_URL"
        [ -n "$HTML_URL" ] && return 0
    done

    return 0
}

fetch_release_meta() {
    if download_github_api "$MOSDNS_API" "$TMP_ROOT/release.json"; then
        return 0
    fi

    warn "GitHub API Get MosDNS Release Information failed, use instead releases Page details"
    download_url "$MOSDNS_RELEASE_URL" "$TMP_ROOT/release.html" || die "Get MosDNS up to date Release Message failed"

    RELEASE_TAG="$(sed -n 's|.*href="/'"$MOSDNS_REPO"'/releases/tag/\([^"/?#]*\)".*|\1|p' "$TMP_ROOT/release.html" | head -n1 || true)"
    if [ -n "$RELEASE_TAG" ]; then
        download_url "https://github.com/$MOSDNS_REPO/releases/expanded_assets/$RELEASE_TAG" "$TMP_ROOT/release-assets.html" || warn "Get MosDNS Release Asset list failed"
    fi
}

get_installed_version() {
    PKG_MGR="$1"
    case "$PKG_MGR" in
        opkg)
            opkg status mosdns 2>/dev/null | sed -n 's/^Version: //p' | head -n1 || true
            ;;
        apk)
            apk info -a mosdns 2>/dev/null | sed -n 's/^version: //p' | head -n1 || true
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

check_runtime() {
    [ -f /etc/openwrt_release ] || die "not detected /etc/openwrt_release, the current environment is not like OpenWrt"
    [ -d /usr/share/luci/menu.d ] || die "current LuCI The version may be too old and not found /usr/share/luci/menu.d"

    ROOT_SPACE="$(df -m /usr | awk 'END{print $4}' 2>/dev/null || printf 0)"
    case "$ROOT_SPACE" in
        ''|*[!0-9]*) ROOT_SPACE=0 ;;
    esac
    if [ "$ROOT_SPACE" -lt 35 ]; then
        die "system /usr Available space is less than 35MB, it is not recommended to continue the installation MosDNS"
    fi
}

install_release_archive() {
    PKG_MGR="$1"
    DISTR_ARCH="$2"
    SDK="$3"
    ASSET_NAME="${DISTR_ARCH}-${SDK}.tar.gz"

    fetch_release_meta
    ASSET_URL="$(find_asset_url "$ASSET_NAME")"
    [ -n "$ASSET_URL" ] || die "Not found for current architecture MosDNS Release Bag: $ASSET_NAME"

    ARCHIVE="$TMP_ROOT/$ASSET_NAME"
    EXTRACT_DIR="$TMP_ROOT/extract"
    mkdir -p "$EXTRACT_DIR"

    log "download MosDNS Release Bag: $ASSET_NAME"
    download_url "$ASSET_URL" "$ARCHIVE" || die "download MosDNS Release Package failed"

    log "Unzip MosDNS Release Bag"
    tar -zxf "$ARCHIVE" -C "$EXTRACT_DIR" || die "Unzip MosDNS Release Package failed"

    if [ -x /etc/init.d/mosdns ]; then
        log "stop MosDNS Serve"
        /etc/init.d/mosdns stop >/dev/null 2>&1 || true
    fi

    case "$PKG_MGR" in
        opkg)
            INSTALL_CMD="opkg install --force-downgrade"
            ;;
        apk)
            INSTALL_CMD="apk add --allow-untrusted"
            ;;
    esac

    log "Install / renew MosDNS Related packages"
    for pkg in \
        "$EXTRACT_DIR"/packages_ci/v2dat*.* \
        "$EXTRACT_DIR"/packages_ci/v2ray-geoip*.* \
        "$EXTRACT_DIR"/packages_ci/v2ray-geosite*.* \
        "$EXTRACT_DIR"/packages_ci/mosdns*.* \
        "$EXTRACT_DIR"/packages_ci/luci-app-mosdns*.* \
        "$EXTRACT_DIR"/packages_ci/luci-i18n-mosdns-zh-cn*.*; do
        [ -f "$pkg" ] || continue
        # shellcheck disable=SC2086
        $INSTALL_CMD "$pkg" || die "Installation failed: $(basename "$pkg")"
    done
}

refresh_luci() {
    rm -rf /tmp/luci-* /tmp/.luci* /tmp/etc/config/ucitrack /var/run/luci-indexcache 2>/dev/null || true
    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd restart >/dev/null 2>&1 || warn "rpcd Restart failed"
    fi
}

restart_mosdns() {
    if [ "$RESTART_SERVICES" != "1" ]; then
        log "Skip by parameter mosdns enable / Restart"
        return 0
    fi

    if [ -x /etc/init.d/mosdns ]; then
        /etc/init.d/mosdns enable >/dev/null 2>&1 || warn "mosdns enable fail"
        /etc/init.d/mosdns restart >/dev/null 2>&1 || warn "mosdns restart fail"
    else
        warn "not found /etc/init.d/mosdns, skip service restart"
    fi
}

main() {
    parse_args "$@"

    if ! mkdir "$LOCKDIR" 2>/dev/null; then
        die "There is already another MosDNS Task is running"
    fi
    mkdir -p "$TMP_ROOT"

    need_cmd sed
    need_cmd grep
    need_cmd head
    need_cmd basename
    need_cmd tar
    need_cmd df
    need_cmd awk

    check_runtime

    PKG_MGR="$(detect_pkg_mgr)"
    DISTR_ARCH="$(get_distr_arch)"
    [ -n "$DISTR_ARCH" ] || die "Unable to read DISTRIB_ARCH, currently does not support the current system"
    SDK="$(select_sdk "$PKG_MGR")"

    log "Package manager detected: $PKG_MGR"
    log "detected MosDNS Architecture: $DISTR_ARCH"
    log "Use build version: $SDK"
    OLD_VER="$(get_installed_version "$PKG_MGR")"
    log "Currently installed version: ${OLD_VER:-not installed}"

    maybe_update_index "$PKG_MGR"
    install_release_archive "$PKG_MGR" "$DISTR_ARCH" "$SDK"
    restart_mosdns
    refresh_luci

    NEW_VER="$(get_installed_version "$PKG_MGR")"
    log "Post-installation version: ${NEW_VER:-unknown}"
    warn "Not actively rewritten by default /etc/config/mosdns;please LuCI Click on your network environment to enable or adjust DNS Offload settings"
    warn "if LuCI The menu does not appear immediately, please refresh the page or log in again LuCI"
    log "MosDNS Processing completed"
}

main "$@"
