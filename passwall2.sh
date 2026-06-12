#!/bin/sh
set -eu

LOCKDIR="/tmp/passwall2-install.lock"
GH_API="https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall2/releases/latest"

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

refresh_luci() {
    rm -rf /tmp/luci-* /tmp/.luci* /tmp/etc/config/ucitrack /var/run/luci-indexcache 2>/dev/null || true
    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd restart >/dev/null 2>&1 || warn "rpcd Restart failed"
    fi
}

download_file() {
    url="$1"
    output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output" 2>/dev/null && return 0
        curl -kfsSL "$url" -o "$output" 2>/dev/null && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qO "$output" "$url" 2>/dev/null && return 0
        wget --no-check-certificate -qO "$output" "$url" 2>/dev/null && return 0
    fi

    return 1
}

fetch_text() {
    url="$1"
    tmp="/tmp/passwall2-page.$$"
    rm -f "$tmp"
    download_file "$url" "$tmp" || return 1
    cat "$tmp"
    rm -f "$tmp"
}

find_pkg_link() {
    page="$1"
    pkg="$2"
    ext="$3"
    printf '%s' "$page" | grep -o 'href="/projects/openwrt-passwall-build/files/[^"]*'"${pkg}"'[-_][^"]*\.'"${ext}"'[^"]*"' | sed 's|^href="||;s|"$||' | head -n1
}

download_pkg_from_dir() {
    pkg="$1"
    dir="$2"
    ext="$3"
    sf_dir_url="https://sourceforge.net/projects/openwrt-passwall-build/files/${PACKAGE_DIR}/${dir}/"
    page="$(fetch_text "$sf_dir_url")" || return 1
    link="$(find_pkg_link "$page" "$pkg" "$ext")"
    [ -n "$link" ] || return 1

    case "$link" in
        */stats/timeline)
            link="${link%/stats/timeline}"
            ;;
    esac

    filename="$(basename "$link")"
    output="/tmp/$filename"
    download_url="https://sourceforge.net${link}/download"

    printf '%s\n' "==> download: $filename" >&2
    download_file "$download_url" "$output" || return 1
    [ -s "$output" ] || return 1
    printf '%s\n' "$output"
}

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    die "There is already another PassWall2 Task is running"
fi

if command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
else
    die "not detected opkg or apk, the current system does not support it yet"
fi

need_cmd "$PKG_MGR"
need_cmd sed
need_cmd grep
need_cmd basename

[ -f /etc/openwrt_release ] || die "not detected /etc/openwrt_release"
# shellcheck disable=SC1091
. /etc/openwrt_release

ARCH="${DISTRIB_ARCH:-}"
REL_RAW="${DISTRIB_RELEASE:-}"
TARGET_NAME="${DISTRIB_TARGET:-}"
[ -n "$ARCH" ] || die "Unable to identify system architecture"
[ -n "$REL_RAW" ] || die "Unable to identify system version"

normalize_release_for_passwall2() {
    rel="$1"
    pkg_mgr="$2"
    case "$rel:$pkg_mgr" in
        25.*:apk) printf '25.12' ;;
        25.*:opkg|24.*:*) printf '24.10' ;;
        23.05*:opkg|23.0*:opkg) printf '23.05' ;;
        22.03*:opkg|22.0*:opkg) printf '22.03' ;;
        *SNAPSHOT*) printf 'snapshots' ;;
        *) printf '' ;;
    esac
}

SUPPORTED_RELEASE="$(normalize_release_for_passwall2 "$REL_RAW" "$PKG_MGR")"
[ -n "$SUPPORTED_RELEASE" ] || die "Current system version ${REL_RAW} / Package manager ${PKG_MGR} Not adapted yet PassWall2 Install script. Recommended OpenWrt 25.12+ apk,or OpenWrt/iStoreOS/ImmortalWrt 22.03,23.05,24.10 opkg Tie."

case "$SUPPORTED_RELEASE" in
    snapshots)
        PACKAGE_DIR="snapshots/packages/$ARCH"
        ;;
    *)
        PACKAGE_DIR="releases/packages-$SUPPORTED_RELEASE/$ARCH"
        ;;
esac

log "System release: $REL_RAW"
log "Arch: $ARCH"
log "Package manager: $PKG_MGR"
[ -n "$TARGET_NAME" ] && log "Target: $TARGET_NAME"
log "Package dir: $PACKAGE_DIR"
if [ "$SUPPORTED_RELEASE" != "$REL_RAW" ]; then
    warn "Current system version ${REL_RAW} Will press the compatible directory ${SUPPORTED_RELEASE} match PassWall2 Software source."
fi
if [ "$PKG_MGR" = "apk" ]; then
    warn "detected OpenWrt 25.12+ apk environment, will try to install the upstream .apk package; will explicitly fail if upstream has not released the current architecture build."
fi

GH_LATEST="$(fetch_text "$GH_API" 2>/dev/null | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
[ -n "$GH_LATEST" ] && log "GitHub latest release: $GH_LATEST"

case "$PKG_MGR" in
    opkg)
        PKG_EXT="ipk"
        OLD_VER="$(opkg status luci-app-passwall2 2>/dev/null | sed -n 's/^Version: //p' | head -n1 || true)"
        ;;
    apk)
        PKG_EXT="apk"
        OLD_VER="$(apk info -a luci-app-passwall2 2>/dev/null | sed -n 's/^version: //p' | head -n1 || true)"
        ;;
    *)
        die "Unknown package manager: $PKG_MGR"
        ;;
esac
log "Currently installed version: ${OLD_VER:-not installed}"
log "Press close to manual ${PKG_EXT} Installed by / renew PassWall2"

MAIN_PKG="$(download_pkg_from_dir luci-app-passwall2 passwall2 "$PKG_EXT")" || die "download luci-app-passwall2 ${PKG_EXT} Failed, please check the current system version/Check whether there is a corresponding build for the architecture, or try again later."
LANG_PKG="$(download_pkg_from_dir luci-i18n-passwall2-zh-cn passwall2 "$PKG_EXT")" || die "download luci-i18n-passwall2-zh-cn ${PKG_EXT} Failed, please try again later."

case "$PKG_MGR" in
    opkg)
        INSTALL_OK=1
        if opkg install "$MAIN_PKG" "$LANG_PKG"; then
            INSTALL_OK=0
        fi
        ;;
    apk)
        INSTALL_OK=1
        apk update || warn "apk update Failure, will continue to try to install the local installation package"
        if apk add --allow-untrusted "$MAIN_PKG" "$LANG_PKG"; then
            INSTALL_OK=0
        fi
        ;;
esac

if [ "$INSTALL_OK" -ne 0 ]; then
    cat >&2 <<EOF
[ERROR] PassWall2 Installation failed.
Possible reasons:
1. The current firmware version is the same as PassWall2 Precompiled package does not match
2. The current architecture lacks corresponding dependency packages, or there is no compatible build in the software source.
3. Third-party firmware rewrites the software source, causing dependency resolution exceptions

Suggested troubleshooting:
- OpenWrt 25.12+ / apk For the environment, please confirm that the upstream has released the corresponding .apk build
- opkg Environment confirmation system version is used first 22.03 / 23.05 / 24.10 Tie
- implement ${PKG_MGR} update Try again later
- Check whether there are any abnormalities or duplicate sources in the system software source configuration
- In the case of non-standard firmware (such as QWRT / GDQ etc.), compatibility depends on whether the upstream provides corresponding builds
EOF
    exit 1
fi

case "$PKG_MGR" in
    opkg) NEW_VER="$(opkg status luci-app-passwall2 2>/dev/null | sed -n 's/^Version: //p' | head -n1 || true)" ;;
    apk) NEW_VER="$(apk info -a luci-app-passwall2 2>/dev/null | sed -n 's/^version: //p' | head -n1 || true)" ;;
esac
log "Post-installation version: ${NEW_VER:-unknown}"

refresh_luci
warn "Not actively modified by default /etc/config/passwall2; If the interface displays abnormally for the first time, you can manually refresh the page or log in again. LuCI"
warn "If the interface is displayed in English for the first time, please refresh the page and the Chinese language pack will automatically take effect."
log "PassWall2 Processing completed"
