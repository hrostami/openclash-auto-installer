#!/bin/sh
set -eu

LOCKDIR="/tmp/nikki-install.lock"
FEED_SCRIPT_URL="https://raw.githubusercontent.com/nikkinikki-org/OpenWrt-nikki/main/feed.sh"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/nikkinikki-org/OpenWrt-nikki/main/install.sh"
NIKKI_REPO_URL="https://nikkinikki.pages.dev"

cleanup() {
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

detect_firewall_stack() {
    if command -v fw4 >/dev/null 2>&1 || [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ]; then
        printf 'nft'
    else
        printf 'iptables'
    fi
}

refresh_luci() {
    rm -rf /tmp/luci-* /tmp/.luci* /tmp/etc/config/ucitrack /var/run/luci-indexcache 2>/dev/null || true
    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd restart >/dev/null 2>&1 || warn "rpcd Restart failed"
    fi
}

detect_nikki_branch() {
    case "${REL_RAW:-}" in
        *24.10*) printf 'openwrt-24.10' ;;
        *25.12*) printf 'openwrt-25.12' ;;
        SNAPSHOT) printf 'SNAPSHOT' ;;
        *) printf '' ;;
    esac
}

add_nikki_apk_feed() {
    branch="$(detect_nikki_branch)"
    [ -n "$branch" ] || die "Current system version ${REL_RAW:-unknown} Not yet Nikki official feed support"

    arch="${DISTRIB_ARCH:-}"
    [ -n "$arch" ] || die "Unable to identify system architecture"

    FEED_URL="$NIKKI_REPO_URL/$branch/$arch/nikki"
    feed_list="/etc/apk/repositories.d/customfeeds.list"

    log "import Nikki apk feed: $FEED_URL"
    mkdir -p /etc/apk/keys /etc/apk/repositories.d
    wget -qO /etc/apk/keys/nikki.pem "$NIKKI_REPO_URL/public-key.pem" || die "download Nikki apk Public key failed"

    if [ -f "$feed_list" ] && grep -q nikki "$feed_list"; then
        sed -i '/nikki/d' "$feed_list"
    fi
    printf '%s\n' "$FEED_URL/packages.adb" >> "$feed_list"
}

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    die "There is already another Nikki Task is running"
fi

[ -f /etc/openwrt_release ] || die "not detected /etc/openwrt_release"
# shellcheck disable=SC1091
. /etc/openwrt_release

REL_RAW="${DISTRIB_RELEASE:-}"
log "System release: ${REL_RAW:-unknown}"

need_cmd wget

if command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
else
    die "not detected opkg or apk"
fi

log "Package manager detected: $PKG_MGR"
FIREWALL_STACK="$(detect_firewall_stack)"
log "Firewall stack detected: $FIREWALL_STACK"
if [ "$FIREWALL_STACK" = "iptables" ]; then
    cat >&2 <<EOF
[ERROR] Nikki Only supports firewall4(nftables)environment.
The current system firewall stack is iptables, so it cannot be installed directly Nikki.

Suggested handling:
- Switch to using firewall4 of OpenWrt / ImmortalWrt / iStoreOS firmware
- or use instead OpenClash / PassWall / PassWall2
EOF
    exit 1
fi
if [ "$PKG_MGR" = "apk" ]; then
    warn "The current package manager is apk(OpenWrt 25.12+),Nikki May not be fully adapted yet."
fi

case "$PKG_MGR" in
    opkg)
        OLD_VER="$(opkg status luci-app-nikki 2>/dev/null | sed -n 's/^Version: //p' | head -n1 || true)"
        log "Currently installed version: ${OLD_VER:-not installed}"
        log "Import according to official method Nikki feed"
        wget -qO- "$FEED_SCRIPT_URL" | sh || die "implement Nikki feed.sh fail"
        log "Install according to the official method / renew Nikki"
        wget -qO- "$INSTALL_SCRIPT_URL" | sh || die "implement Nikki official install.sh fail"
        opkg install luci-i18n-nikki-zh-cn || warn "Install Nikki Chinese language pack failed"
        NEW_VER="$(opkg status luci-app-nikki 2>/dev/null | sed -n 's/^Version: //p' | head -n1 || true)"
        ;;
    apk)
        OLD_VER="$(apk info -a luci-app-nikki 2>/dev/null | sed -n 's/^version: //p' | head -n1 || true)"
        log "Currently installed version: ${OLD_VER:-not installed}"
        add_nikki_apk_feed
        log "Refresh software source"
        apk update || die "apk update Failed, please check Nikki feed or network connection"
        log "according to Nikki official apk feed Install / renew Nikki"
        apk add --allow-untrusted -X "$FEED_URL/packages.adb" mihomo-meta nikki luci-app-nikki || die "Install Nikki apk Package failed, please check if the current schema exists Nikki Official build"
        apk add --allow-untrusted -X "$FEED_URL/packages.adb" luci-i18n-nikki-zh-cn || warn "Install Nikki Chinese language pack failed"
        NEW_VER="$(apk info -a luci-app-nikki 2>/dev/null | sed -n 's/^version: //p' | head -n1 || true)"
        ;;
esac

log "Post-installation version: ${NEW_VER:-unknown}"
refresh_luci
warn "Not actively rewritten by default Nikki Configuration; if the interface displays abnormally for the first time, you can manually refresh the page or log in again. LuCI"
warn "If the interface is displayed in English for the first time, please refresh the page and the Chinese language pack will automatically take effect."
log "Nikki Processing completed"
