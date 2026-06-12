#!/bin/sh
set -eu

LOCKDIR="/tmp/passwall-install.lock"
GH_API="https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall/releases/latest"
GH_REPO_PAGE="https://github.com/Openwrt-Passwall/openwrt-passwall"
SF_BASE="https://sourceforge.net/projects/openwrt-passwall-build/files"
TMPFILES=""

register_tmp() {
    TMPFILES="$TMPFILES $1"
}

cleanup() {
    rmdir "$LOCKDIR" 2>/dev/null || true
    for f in $TMPFILES; do
        rm -f "$f" 2>/dev/null || true
    done
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
        curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$output" && return 0
        warn "curl Download failed (will try again skipping certificate verification): $url"
        curl -kfsSL --retry 2 --connect-timeout 15 "$url" -o "$output" && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qO "$output" "$url" && return 0
        warn "wget Download failed (will try again skipping certificate verification): $url"
        wget --no-check-certificate -qO "$output" "$url" && return 0
    fi

    return 1
}

fetch_text() {
    url="$1"
    tmp="$(mktemp /tmp/passwall-page.XXXXXX)"
    register_tmp "$tmp"
    download_file "$url" "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    cat "$tmp"
    rm -f "$tmp"
}

find_pkg_link() {
    page="$1"
    pkg="$2"
    ext="$3"
    link="$(printf '%s' "$page" | grep -o 'href="/projects/openwrt-passwall-build/files/[^"]*'"${pkg}"'[-_][^"]*\.'"${ext}"'[^"]*"' | sed 's|^href="||;s|"$||' | head -n1)"
    if [ -z "$link" ]; then
        warn "exist SourceForge Package not found in page: $pkg"
        return 1
    fi
    printf '%s\n' "$link"
}

download_pkg_from_dir() {
    pkg="$1"
    dir="$2"
    ext="$3"
    sf_dir_url="${SF_BASE}/${PACKAGE_DIR}/${dir}/"
    page="$(fetch_text "$sf_dir_url")" || {
        warn "Unable to get directory page: $sf_dir_url"
        return 1
    }
    link="$(find_pkg_link "$page" "$pkg" "$ext")" || return 1

    case "$link" in
        */stats/timeline)
            link="${link%/stats/timeline}"
            ;;
    esac

    filename="$(basename "$link")"
    output="/tmp/$filename"
    register_tmp "$output"
    download_url="https://sourceforge.net${link}/download"

    log "download: $filename" >&2
    download_file "$download_url" "$output" || {
        warn "Download failed: $download_url"
        return 1
    }
    [ -s "$output" ] || {
        warn "Download file is empty: $output"
        return 1
    }
    printf '%s\n' "$output"
}

github_release_prefix() {
    case "$PKG_MGR:$SUPPORTED_RELEASE" in
        apk:*) printf '25.12+_' ;;
        opkg:24.10|opkg:23.05) printf '23.05-24.10_' ;;
        opkg:22.03) printf '22.03-_' ;;
        *) printf '' ;;
    esac
}

fetch_github_latest_tag_page() {
    page="$(fetch_text "${GH_REPO_PAGE}/releases/latest")" || return 1
    printf '%s\n' "$page" \
        | sed -n 's|.*href="/Openwrt-Passwall/openwrt-passwall/releases/tag/\([^"/?#]*\)".*|\1|p' \
        | head -n1
}

fetch_github_release_asset_urls_page() {
    tag="$1"
    [ -n "$tag" ] || return 1
    page="$(fetch_text "${GH_REPO_PAGE}/releases/expanded_assets/${tag}")" || return 1
    printf '%s\n' "$page" \
        | sed -n 's|.*href="\(/Openwrt-Passwall/openwrt-passwall/releases/download/[^"]*\)".*|https://github.com\1|p'
}

find_github_pkg_url() {
    pkg="$1"
    ext="$2"
    prefix="$(github_release_prefix)"
    [ -n "$prefix" ] || return 1
    {
        if [ -n "${GH_RELEASE_JSON:-}" ]; then
            printf '%s\n' "$GH_RELEASE_JSON" \
                | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p'
        fi
        [ -z "${GH_RELEASE_ASSET_URLS:-}" ] || printf '%s\n' "$GH_RELEASE_ASSET_URLS"
    } \
        | sed 's/%2B/+/g' \
        | grep "/${prefix}[^/]*${pkg}[^/]*\.${ext}$" \
        | head -n1
}

download_pkg_from_github_release() {
    pkg="$1"
    ext="$2"
    url="$(find_github_pkg_url "$pkg" "$ext")"
    [ -n "$url" ] || {
        warn "GitHub release assets Package not found in: $pkg"
        return 1
    }

    filename="$(basename "$url" | sed 's/%2B/+/g')"
    output="/tmp/$filename"
    register_tmp "$output"

    log "download: $filename" >&2
    download_file "$url" "$output" || download_file "https://gh-proxy.com/$url" "$output" || {
            warn "Download failed: $url"
            return 1
        }
    [ -s "$output" ] || {
        warn "Download file is empty: $output"
        return 1
    }
    printf '%s\n' "$output"
}

download_passwall_pkg() {
    pkg="$1"
    dir="$2"
    ext="$3"

    if [ -n "${GH_RELEASE_JSON:-}${GH_RELEASE_ASSET_URLS:-}" ]; then
        download_pkg_from_github_release "$pkg" "$ext" && return 0
        warn "GitHub release assets Download failed, rolled back SourceForge Table of contents."
    fi

    download_pkg_from_dir "$pkg" "$dir" "$ext"
}

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    die "There is already another PassWall Task is running"
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
need_cmd mktemp

[ -f /etc/openwrt_release ] || die "not detected /etc/openwrt_release"
# shellcheck disable=SC1091
. /etc/openwrt_release

ARCH="${DISTRIB_ARCH:-}"
REL_RAW="${DISTRIB_RELEASE:-}"
TARGET_NAME="${DISTRIB_TARGET:-}"
[ -n "$ARCH" ] || die "Unable to identify system architecture"
[ -n "$REL_RAW" ] || die "Unable to identify system version"

normalize_release_for_passwall() {
    rel="$1"
    pkg_mgr="$2"
    case "$rel:$pkg_mgr" in
        25.*:apk) printf '25.12' ;;
        25.*:opkg|24.[0-9]*:*) printf '24.10' ;;
        23.05:opkg|23.05.[0-9]*:opkg) printf '23.05' ;;
        22.03:opkg|22.03.[0-9]*:opkg) printf '22.03' ;;
        *SNAPSHOT*) printf 'snapshots' ;;
        *) printf '' ;;
    esac
}

SUPPORTED_RELEASE="$(normalize_release_for_passwall "$REL_RAW" "$PKG_MGR")"
[ -n "$SUPPORTED_RELEASE" ] || die "Current system version ${REL_RAW} / Package manager ${PKG_MGR} Not adapted yet PassWall Install script. Recommended OpenWrt 25.12+ apk,or OpenWrt/iStoreOS/ImmortalWrt 22.03,23.05,24.10 opkg Tie."

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
    warn "Current system version ${REL_RAW} Will press the compatible directory ${SUPPORTED_RELEASE} match PassWall Software source."
fi
if [ "$PKG_MGR" = "apk" ]; then
    warn "detected OpenWrt 25.12+ apk environment, will try to install the upstream .apk package; will explicitly fail if upstream has not released the current architecture build."
fi

GH_RELEASE_JSON="$(fetch_text "$GH_API" 2>/dev/null || true)"
GH_LATEST="$(printf '%s' "$GH_RELEASE_JSON" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
if [ -z "$GH_LATEST" ]; then
    GH_LATEST="$(fetch_github_latest_tag_page 2>/dev/null || true)"
fi
[ -n "$GH_LATEST" ] && log "GitHub latest release: $GH_LATEST"
GH_RELEASE_ASSET_URLS=""
if [ -z "$GH_RELEASE_JSON" ] && [ -n "$GH_LATEST" ]; then
    GH_RELEASE_ASSET_URLS="$(fetch_github_release_asset_urls_page "$GH_LATEST" 2>/dev/null || true)"
    [ -n "$GH_RELEASE_ASSET_URLS" ] && log "GitHub release assets: Obtained through web page"
fi

case "$PKG_MGR" in
    opkg)
        PKG_EXT="ipk"
        OLD_VER="$(opkg status luci-app-passwall 2>/dev/null | sed -n 's/^Version: //p' | head -n1 || true)"
        ;;
    apk)
        PKG_EXT="apk"
        OLD_VER="$(apk info -a luci-app-passwall 2>/dev/null | sed -n 's/^version: //p' | head -n1 || true)"
        ;;
    *)
        die "Unknown package manager: $PKG_MGR"
        ;;
esac
log "Currently installed version: ${OLD_VER:-not installed}"
log "Press close to manual ${PKG_EXT} Installed by / renew PassWall"

install_lyaml_fallback() {
    case "$SUPPORTED_RELEASE" in
        24.10)
            dep_path="releases/${REL_RAW}/packages/${ARCH}/packages"
            ;;
        *)
            return 1
            ;;
    esac

    for mirror in \
        "https://downloads.openwrt.org" \
        "https://mirrors.tuna.tsinghua.edu.cn/openwrt" \
        "https://mirrors.ustc.edu.cn/openwrt" \
        "https://mirrors.aliyun.com/openwrt" \
        "https://mirrors.cernet.edu.cn/openwrt"
    do
        dep_base="${mirror}/${dep_path}"
        log "Software source installation lyaml failed, try from ${dep_base} Download dependencies directly IPK"
        dir_page="$(fetch_text "${dep_base}/")" || {
            warn "Unable to obtain dependency directory: ${dep_base}/"
            continue
        }

        libyaml_name="$(printf '%s' "$dir_page" | grep -o "libyaml_[^\"'<>]*_${ARCH}\.ipk" | head -n1)"
        lyaml_name="$(printf '%s' "$dir_page" | grep -o "lyaml_[^\"'<>]*_${ARCH}\.ipk" | head -n1)"
        [ -n "$libyaml_name" ] || {
            warn "not found libyaml IPK(Architecture: $ARCH)"
            continue
        }
        [ -n "$lyaml_name" ] || {
            warn "not found lyaml IPK(Architecture: $ARCH)"
            continue
        }

        libyaml_ipk="/tmp/$libyaml_name"
        lyaml_ipk="/tmp/$lyaml_name"
        register_tmp "$libyaml_ipk"
        register_tmp "$lyaml_ipk"

        log "Download dependencies: $libyaml_name"
        download_file "${dep_base}/${libyaml_name}" "$libyaml_ipk" || continue
        log "Download dependencies: $lyaml_name"
        download_file "${dep_base}/${lyaml_name}" "$lyaml_ipk" || continue

        opkg install "$libyaml_ipk" "$lyaml_ipk" && return 0
    done

    return 1
}

if [ "$PKG_MGR" = "opkg" ] && ! opkg list-installed lyaml 2>/dev/null | grep -q '^lyaml -'; then
    log "Install dependencies: lyaml"
    opkg update || warn "opkg update If it fails, it will continue to try to install cached software source dependencies."
    opkg install lyaml || install_lyaml_fallback || die "Install dependencies lyaml fail. Please check whether the system software source is enabled packages source, or execute manually: opkg update && opkg install lyaml"
fi

MAIN_PKG="$(download_passwall_pkg luci-app-passwall passwall_luci "$PKG_EXT")" || die "download luci-app-passwall ${PKG_EXT} Failed, please check the current system version/Check whether there is a corresponding build for the architecture, or try again later."
LANG_PKG="$(download_passwall_pkg luci-i18n-passwall-zh-cn passwall_luci "$PKG_EXT")" || die "download luci-i18n-passwall-zh-cn ${PKG_EXT} Failed, please try again later."

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
[ERROR] PassWall Installation failed.
Possible reasons:
1. The current firmware version is the same as PassWall Precompiled package does not match
2. The current architecture lacks corresponding dependency packages, or there is no compatible build in the software source.
3. Third-party firmware rewrites the software source, causing dependency resolution exceptions

Suggested troubleshooting:
- OpenWrt 25.12+ / apk For the environment, please confirm that the upstream has released the corresponding .apk build
- opkg Environment confirmation system version is used first 22.03 / 23.05 / 24.10 Tie
- implement ${PKG_MGR} update Try again later
- Check whether there are any abnormalities or duplicate sources in the system software source configuration
- If so iStoreOS 24.10 / Non-standard firmware can be used with priority OpenClash,PassWall Compatibility depends on upstream build
EOF
    exit 1
fi

case "$PKG_MGR" in
    opkg) NEW_VER="$(opkg status luci-app-passwall 2>/dev/null | sed -n 's/^Version: //p' | head -n1 || true)" ;;
    apk) NEW_VER="$(apk info -a luci-app-passwall 2>/dev/null | sed -n 's/^version: //p' | head -n1 || true)" ;;
esac
log "Post-installation version: ${NEW_VER:-unknown}"

refresh_luci
warn "Not actively modified by default /etc/config/passwall; If the interface displays abnormally for the first time, you can manually refresh the page or log in again. LuCI"
warn "If the interface is displayed in English for the first time, please refresh the page and the Chinese language pack will automatically take effect."
log "PassWall Processing completed"
