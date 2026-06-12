#!/bin/sh
set -eu

# OpenClash One click installation / update script
# Applicable scenarios:OpenWrt / iStoreOS / ImmortalWrt etc. Compatible opkg / apk environment

LOCKDIR="/tmp/openclash-auto-install.lock"
TMP_ROOT="/tmp/openclash-auto-install"
API_URL="https://api.github.com/repos/vernesong/OpenClash/releases/latest"
CORE_REPO_BASE_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master"
SCRIPT_NAME="openclash-auto-install"
MODE="full"
RESTART_SERVICES="1"
FORCE_OPKG_UPDATE="1"
CORE_CHANNEL="auto"
OPKG_RETRY_SECONDS="10"
CHECK_ONLY="0"

cleanup() {
    rm -rf "$TMP_ROOT"
    rmdir "$LOCKDIR" 2>/dev/null || true
}

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
  sh install.sh [Options]

Options:
  --plugin-only       Install only/renew OpenClash Plug-in, not installed Meta Kernel
  --core-only         Just download and install Meta Kernel, not installed/Update plugin
  --check-update      Only checks if there is a new version and does not perform installation/renew
  --meta-core         Force normal Meta Kernel
  --smart-core        Mandatory use Smart Meta Kernel
  --skip-restart      Do not attempt to restart after completion openclash / uhttpd
  --skip-pkg-update   Skip software source updates (opkg update / apk update)
  --skip-opkg-update  Compatible with old parameters, equivalent to --skip-pkg-update
  -h, --help          show help
EOF_USAGE
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --plugin-only)
                MODE="plugin-only"
                ;;
            --core-only)
                MODE="core-only"
                ;;
            --meta-core)
                CORE_CHANNEL="meta"
                ;;
            --smart-core)
                CORE_CHANNEL="smart"
                ;;
            --check-update)
                CHECK_ONLY="1"
                ;;
            --skip-restart)
                RESTART_SERVICES="0"
                ;;
            --skip-pkg-update|--skip-opkg-update)
                FORCE_OPKG_UPDATE="0"
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

trap cleanup EXIT INT TERM

parse_args "$@"

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    die "There is already another installation/Update task is running"
fi

mkdir -p "$TMP_ROOT"

get_distr_arch() {
    if [ -f /etc/openwrt_release ]; then
        # shellcheck disable=SC1091
        . /etc/openwrt_release >/dev/null 2>&1 || true
        printf '%s' "${DISTRIB_ARCH:-}"
    else
        printf ''
    fi
}

get_distr_release() {
    if [ -f /etc/openwrt_release ]; then
        # shellcheck disable=SC1091
        . /etc/openwrt_release >/dev/null 2>&1 || true
        printf '%s' "${DISTRIB_RELEASE:-}"
    else
        printf ''
    fi
}

has_flag() {
    printf ' %s ' "${CPU_FLAGS:-}" | grep -qw "$1"
}

detect_x86_level() {
    CPU_FLAGS="$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null | cut -d: -f2- || true)"

    if has_flag avx512f && has_flag avx512bw && has_flag avx512cd && has_flag avx512dq && has_flag avx512vl; then
        printf 'v4'
        return
    fi

    if has_flag avx && has_flag avx2 && has_flag bmi1 && has_flag bmi2 && has_flag f16c && has_flag fma && has_flag lzcnt && has_flag movbe && has_flag xsave; then
        printf 'v3'
        return
    fi

    if has_flag cx16 && has_flag lahf_lm && has_flag popcnt && has_flag ssse3 && has_flag sse4_1 && has_flag sse4_2; then
        printf 'v2'
        return
    fi

    printf 'v1'
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

detect_firewall_stack() {
    if command -v fw4 >/dev/null 2>&1 || [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ]; then
        printf 'nft'
    else
        printf 'iptables'
    fi
}

detect_core_candidates() {
    RAW_ARCH="$(uname -m 2>/dev/null || true)"
    DIST_ARCH="$(get_distr_arch)"
    MATCH_STR="$RAW_ARCH $DIST_ARCH"

    case "$MATCH_STR" in
        *x86_64*|*amd64*)
            X86_LEVEL="$(detect_x86_level)"
            case "$X86_LEVEL" in
                v4) printf '%s' 'clash-linux-amd64-v4.tar.gz clash-linux-amd64-v3.tar.gz clash-linux-amd64-v2.tar.gz clash-linux-amd64.tar.gz' ;;
                v3) printf '%s' 'clash-linux-amd64-v3.tar.gz clash-linux-amd64-v2.tar.gz clash-linux-amd64.tar.gz' ;;
                v2) printf '%s' 'clash-linux-amd64-v2.tar.gz clash-linux-amd64.tar.gz' ;;
                *)  printf '%s' 'clash-linux-amd64.tar.gz' ;;
            esac
            ;;
        *aarch64*|*arm64*|*armv8*)
            printf '%s' 'clash-linux-arm64.tar.gz'
            ;;
        *armv7*|*arm_cortex-a7*|*arm_cortex-a9*|*arm_cortex-a15*)
            printf '%s' 'clash-linux-armv7.tar.gz'
            ;;
        *armv6*|*arm1176*|*arm_arm1176*)
            printf '%s' 'clash-linux-armv6.tar.gz'
            ;;
        *armv5*|*arm926*)
            printf '%s' 'clash-linux-armv5.tar.gz'
            ;;
        *)
            printf ''
            ;;
    esac
}

download_file() {
    URL="$1"
    OUT="$2"
    if ! curl -fsSL --retry 3 --connect-timeout 15 "$URL" -o "$OUT"; then
        return 1
    fi
    return 0
}

is_openclash_installed() {
    PKG_MGR="$1"
    case "$PKG_MGR" in
        opkg)
            opkg status luci-app-openclash 2>/dev/null | grep -q '^Status: .* installed'
            ;;
        apk)
            apk info -e luci-app-openclash >/dev/null 2>&1
            ;;
    esac
}

get_installed_openclash_version() {
    PKG_MGR="$1"
    if ! is_openclash_installed "$PKG_MGR"; then
        return 0
    fi

    case "$PKG_MGR" in
        opkg)
            opkg status luci-app-openclash 2>/dev/null | sed -n 's/^Version: //p' | head -n1
            ;;
        apk)
            apk info -a luci-app-openclash 2>/dev/null | sed -n 's/^version: //p' | head -n1
            ;;
    esac
}

maybe_update_index_opkg() {
    if [ "$FORCE_OPKG_UPDATE" != "1" ]; then
        log "Skip by parameter opkg update"
        return 0
    fi

    log "renew opkg software index"
    if opkg update; then
        return 0
    fi

    if [ -e /var/lock/opkg.lock ]; then
        warn "detected opkg.lock, there may be other package management tasks running"
        warn "will be in ${OPKG_RETRY_SECONDS} Try again after seconds opkg update"
        sleep "$OPKG_RETRY_SECONDS"
        if opkg update; then
            return 0
        fi
    fi

    warn "opkg update Not entirely successful, possibly a third party feed Temporarily unavailable"
    warn "Will continue to try to install; if subsequent dependency installation fails, please fix it /etc/opkg/customfeeds.conf Try again later"
    return 0
}

maybe_update_index_apk() {
    if [ "$FORCE_OPKG_UPDATE" = "1" ]; then
        log "renew apk software index"
        apk update
    else
        log "Skip by parameter apk update"
    fi
}

install_dependencies_opkg() {
    FIREWALL_STACK="$1"
    maybe_update_index_opkg

    if [ "$FIREWALL_STACK" = "nft" ]; then
        PKGS="bash dnsmasq-full curl ca-bundle ip-full kmod-tun kmod-inet-diag unzip kmod-nft-tproxy jsonfilter"
    else
        PKGS="bash iptables dnsmasq-full curl ca-bundle ipset ip-full iptables-mod-tproxy iptables-mod-extra kmod-tun kmod-inet-diag unzip jsonfilter"
    fi

    log "Install minimal dependency packages"
    opkg install $PKGS
}

install_dependencies_apk() {
    FIREWALL_STACK="$1"
    maybe_update_index_apk

    if [ "$FIREWALL_STACK" = "nft" ]; then
        PKGS="bash dnsmasq-full curl ca-bundle ip-full kmod-tun kmod-inet-diag unzip kmod-nft-tproxy jsonfilter"
    else
        PKGS="bash iptables dnsmasq-full curl ca-bundle ipset ip-full iptables-mod-tproxy iptables-mod-extra kmod-tun kmod-inet-diag unzip jsonfilter"
    fi

    log "Install minimal dependency packages"
    apk add $PKGS
}

fetch_openclash_release_meta() {
    VERSION_JSON="$TMP_ROOT/openclash_version.json"
    printf '%s\n' "==> Get OpenClash Latest release information" >&2
    if download_file "$API_URL" "$VERSION_JSON"; then
        return 0
    fi

    warn "GitHub API Failed to obtain, try to fall back to releases Page parsing"
    return 1
}

get_latest_tag() {
    VERSION_JSON="$TMP_ROOT/openclash_version.json"

    if [ -f "$VERSION_JSON" ]; then
        jsonfilter -i "$VERSION_JSON" -e '@.tag_name' 2>/dev/null || true
        return 0
    fi

    curl -fsSI --retry 3 https://github.com/vernesong/OpenClash/releases/latest 2>/dev/null | sed -n 's#^location: .*releases/tag/\([^\r]*\)\r$#\1#Ip' | head -n1
}

normalize_version() {
    VER="$1"
    VER="${VER#v}"
    VER="${VER%%-*}"
    printf '%s' "$VER"
}

check_update_only() {
    PKG_MGR="$1"
    OLD_VER="$(get_installed_openclash_version "$PKG_MGR" || true)"

    need_cmd jsonfilter
    fetch_openclash_release_meta || true
    LATEST_TAG="$(get_latest_tag)"

    log "Currently installed version: ${OLD_VER:-not installed}"
    log "OpenClash Latest release tags: ${LATEST_TAG:-unknown}"

    if [ -z "${LATEST_TAG:-}" ]; then
        die "Failed to get latest version"
    fi

    if [ -z "${OLD_VER:-}" ]; then
        log "Not currently installed OpenClash, you can directly perform the installation"
        return 0
    fi

    OLD_NORM="$(normalize_version "$OLD_VER")"
    LATEST_NORM="$(normalize_version "$LATEST_TAG")"

    if [ "$OLD_NORM" = "$LATEST_NORM" ]; then
        log "It is already the latest version, no need to update"
    else
        log "New version detected and can be updated"
        log "If you need to update, you can execute: sh install.sh --skip-pkg-update"
        log "If you want to update only the plug-in, you can execute: sh install.sh --plugin-only --skip-pkg-update"
    fi
}

fetch_openclash_package_url() {
    PKG_MGR="$1"
    VERSION_JSON="$TMP_ROOT/openclash_version.json"
    OPENCLASH_PKG_URL=""

    if [ ! -f "$VERSION_JSON" ]; then
        fetch_openclash_release_meta || true
    fi

    if [ -f "$VERSION_JSON" ]; then
        if [ "$PKG_MGR" = "opkg" ]; then
            OPENCLASH_PKG_URL="$(jsonfilter -i "$VERSION_JSON" -e '@.assets[*].browser_download_url' | grep -E '/luci-app-openclash_.*_all\.ipk$' | head -n1 || true)"
            [ -n "$OPENCLASH_PKG_URL" ] || OPENCLASH_PKG_URL="$(jsonfilter -i "$VERSION_JSON" -e '@.assets[*].browser_download_url' | grep '\.ipk$' | head -n1 || true)"
        else
            OPENCLASH_PKG_URL="$(jsonfilter -i "$VERSION_JSON" -e '@.assets[*].browser_download_url' | grep -E '/luci-app-openclash-.*\.apk$' | head -n1 || true)"
            [ -n "$OPENCLASH_PKG_URL" ] || OPENCLASH_PKG_URL="$(jsonfilter -i "$VERSION_JSON" -e '@.assets[*].browser_download_url' | grep '\.apk$' | head -n1 || true)"
        fi
    fi

    if [ -z "$OPENCLASH_PKG_URL" ]; then
        TAG="$(get_latest_tag)"
        [ -n "$TAG" ] || die "not found OpenClash Latest version label"
        ASSETS_HTML="$TMP_ROOT/openclash_assets.html"
        download_file "https://github.com/vernesong/OpenClash/releases/expanded_assets/$TAG" "$ASSETS_HTML" || die "Get OpenClash Resource list failed"
        if [ "$PKG_MGR" = "opkg" ]; then
            OPENCLASH_PKG_URL="$(grep -o '/vernesong/OpenClash/releases/download/[^"'"'"']*luci-app-openclash[^"'"'"']*\.ipk' "$ASSETS_HTML" | head -n1 || true)"
        else
            OPENCLASH_PKG_URL="$(grep -o '/vernesong/OpenClash/releases/download/[^"'"'"']*luci-app-openclash[^"'"'"']*\.apk' "$ASSETS_HTML" | head -n1 || true)"
        fi
        [ -n "$OPENCLASH_PKG_URL" ] && OPENCLASH_PKG_URL="https://github.com$OPENCLASH_PKG_URL"
    fi

    [ -n "$OPENCLASH_PKG_URL" ] || die "No match found for the current package manager OpenClash Installation package"
    printf '%s' "$OPENCLASH_PKG_URL"
}

install_openclash_package() {
    PKG_MGR="$1"
    DOWNLOAD_URL="$2"

    case "$PKG_MGR" in
        opkg)
            PKG_FILE="$TMP_ROOT/openclash.ipk"
            log "download OpenClash IPK: $DOWNLOAD_URL"
            download_file "$DOWNLOAD_URL" "$PKG_FILE" || die "download OpenClash IPK fail"
            opkg install "$PKG_FILE"
            ;;
        apk)
            PKG_FILE="$TMP_ROOT/openclash.apk"
            log "download OpenClash APK: $DOWNLOAD_URL"
            download_file "$DOWNLOAD_URL" "$PKG_FILE" || die "download OpenClash APK fail"
            apk add -q --force-overwrite --clean-protected --allow-untrusted "$PKG_FILE"
            ;;
        *)
            die "Unknown package manager: $PKG_MGR"
            ;;
    esac
}

detect_smart_core_enabled() {
    if command -v uci >/dev/null 2>&1; then
        SMART_VALUE="$(uci -q get openclash.config.smart_enable 2>/dev/null || true)"
        case "$SMART_VALUE" in
            1|true|TRUE|True|on|ON|yes|YES)
                printf '%s' 'smart'
                return
                ;;
        esac

        SMART_VALUE="$(uci -q get openclash.config.enable_meta_core 2>/dev/null || true)"
        case "$SMART_VALUE" in
            1|true|TRUE|True|on|ON|yes|YES)
                printf '%s' 'smart'
                return
                ;;
        esac

        SMART_VALUE="$(uci -q get openclash.config.enable_meta_core_fast 2>/dev/null || true)"
        case "$SMART_VALUE" in
            1|true|TRUE|True|on|ON|yes|YES)
                printf '%s' 'smart'
                return
                ;;
        esac
    fi

    printf '%s' 'meta'
}

resolve_core_channel() {
    case "$CORE_CHANNEL" in
        smart)
            printf '%s' 'smart'
            ;;
        meta)
            printf '%s' 'meta'
            ;;
        auto)
            detect_smart_core_enabled
            ;;
        *)
            printf '%s' 'meta'
            ;;
    esac
}

download_core() {
    CHANNEL="$1"
    CANDIDATES="$2"
    TMP_CORE="$TMP_ROOT/openclash-core.tar.gz"
    CORE_BASE_URL="$CORE_REPO_BASE_URL/$CHANNEL"

    rm -f "$TMP_CORE"

    for file in $CANDIDATES; do
        URL="$CORE_BASE_URL/$file"
        log "try download ${CHANNEL} Kernel: $URL"
        if download_file "$URL" "$TMP_CORE"; then
            CHOSEN_CORE_FILE="$file"
            CHOSEN_CORE_CHANNEL="$CHANNEL"
            export CHOSEN_CORE_FILE CHOSEN_CORE_CHANNEL
            return 0
        fi
    done

    return 1
}

extract_and_install_core() {
    TMP_CORE="$TMP_ROOT/openclash-core.tar.gz"
    TMP_DIR="$TMP_ROOT/core-extract"

    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    mkdir -p /etc/openclash/core

    tar zxf "$TMP_CORE" -C "$TMP_DIR" >/dev/null 2>&1 || die "Unzip Meta Kernel failed"

    BIN_FILE="$(find "$TMP_DIR" -type f -perm -u+x 2>/dev/null | head -n1 || true)"
    [ -n "$BIN_FILE" ] || BIN_FILE="$(find "$TMP_DIR" -type f 2>/dev/null | head -n1 || true)"
    [ -n "$BIN_FILE" ] || die "No available files found in the kernel archive"

    if [ -f /etc/openclash/core/clash_meta ]; then
        cp -f /etc/openclash/core/clash_meta /etc/openclash/core/clash_meta.bak 2>/dev/null || true
    fi

    cp -f "$BIN_FILE" /etc/openclash/core/clash_meta
    chmod 0755 /etc/openclash/core/clash_meta

    log "Meta The kernel has been installed to /etc/openclash/core/clash_meta"
}

restart_related_services() {
    CHANGED="${1:-1}"

    if [ "$RESTART_SERVICES" != "1" ]; then
        log "Skip service restart by parameter"
        return 0
    fi

    if [ "$CHANGED" != "1" ]; then
        log "The version has not changed and no forced changes have been made. Service restart is skipped."
        return 0
    fi

    if [ -x /etc/init.d/openclash ]; then
        log "Try restarting OpenClash Serve"
        /etc/init.d/openclash restart >/dev/null 2>&1 || warn "OpenClash The service restart failed and can be restarted manually later."
    fi

    log "clean up LuCI menu cache"
    rm -rf /tmp/luci-* /tmp/.luci* /tmp/etc/config/ucitrack /var/run/luci-indexcache 2>/dev/null || true

    if [ -x /etc/init.d/rpcd ]; then
        log "Try restarting rpcd"
        /etc/init.d/rpcd restart >/dev/null 2>&1 || warn "rpcd Restart failed, you can manually restart later"
    fi
}

show_runtime_versions() {
    if [ -n "${NEW_VER:-}" ]; then
        log "current OpenClash Plugin version: ${NEW_VER}"
    elif [ -n "${OLD_VER:-}" ]; then
        log "current OpenClash Plugin version: ${OLD_VER}"
    fi

    if [ -n "${CHOSEN_CORE_CHANNEL:-}" ]; then
        log "This time the core channel is installed: ${CHOSEN_CORE_CHANNEL}"
    fi

    if [ -x /etc/openclash/core/clash_meta ]; then
        CORE_VER="$(/etc/openclash/core/clash_meta -v 2>/dev/null | head -n1 || true)"
        if [ -n "$CORE_VER" ]; then
            log "current Meta Kernel version: $CORE_VER"
        else
            warn "Detected clash_meta file, but could not read version information"
        fi
    else
        warn "not detected /etc/openclash/core/clash_meta"
    fi
}

show_summary() {
    cat <<EOF_SUMMARY
==> Finish
==> Suggested next steps:
 1. refresh LuCI page
 2. Enter Serve -> OpenClash
 3. If the kernel version on the page is not refreshed in time, please refer to the command line output.
 4. Import the subscription and then start it
EOF_SUMMARY
}

main() {
    need_cmd curl
    need_cmd tar
    need_cmd grep
    need_cmd head
    need_cmd find
    need_cmd sed

    PKG_MGR="$(detect_pkg_mgr)"
    FIREWALL_STACK="$(detect_firewall_stack)"
    RAW_ARCH="$(uname -m 2>/dev/null || true)"
    DIST_ARCH="$(get_distr_arch)"
    DIST_RELEASE="$(get_distr_release)"
    OLD_VER="$(get_installed_openclash_version "$PKG_MGR" || true)"
    PLUGIN_CHANGED="0"
    CORE_CHANGED="0"

    log "Script name: $SCRIPT_NAME"
    log "execution mode: $MODE"
    log "Core channel strategy: $CORE_CHANNEL"
    log "Package manager: $PKG_MGR"
    log "firewall stack: $FIREWALL_STACK"
    log "uname -m: ${RAW_ARCH:-unknown}"
    log "DISTRIB_ARCH: ${DIST_ARCH:-unknown}"
    [ -n "$DIST_RELEASE" ] && log "DISTRIB_RELEASE: $DIST_RELEASE"
    if [ -n "$DIST_RELEASE" ] && printf '%s\n' "$DIST_RELEASE" | grep -q '^25\.12'; then
        if [ "$PKG_MGR" = "apk" ]; then
            warn "detected OpenWrt 25.12+ and apk package manager, press apk Compatible path installation."
            warn "If the installation fails, please keep the complete log. Usually the upstream package or system dependency has not been adapted."
        else
            warn "detected OpenWrt 25.12+, but the package manager is $PKG_MGR, please confirm whether the current environment is normal."
        fi
    fi
    log "Currently installed version: ${OLD_VER:-not installed}"

    if [ "$CHECK_ONLY" = "1" ]; then
        check_update_only "$PKG_MGR"
        exit 0
    fi

    case "$MODE" in
        full|plugin-only)
            case "$PKG_MGR" in
                opkg) install_dependencies_opkg "$FIREWALL_STACK" ;;
                apk) install_dependencies_apk "$FIREWALL_STACK" ;;
            esac
            need_cmd jsonfilter
            fetch_openclash_release_meta || true
            LATEST_TAG="$(get_latest_tag)"
            [ -n "$LATEST_TAG" ] && log "OpenClash Latest release tags: $LATEST_TAG"
            PACKAGE_URL="$(fetch_openclash_package_url "$PKG_MGR")"
            log "Install / renew OpenClash plug-in"
            install_openclash_package "$PKG_MGR" "$PACKAGE_URL"
            NEW_VER="$(get_installed_openclash_version "$PKG_MGR" || true)"
            log "Post-installation version: ${NEW_VER:-unknown}"
            if [ "${OLD_VER:-}" != "${NEW_VER:-}" ]; then
                PLUGIN_CHANGED="1"
            fi
            ;;
    esac

    case "$MODE" in
        full|core-only)
            CORE_CANDIDATES="$(detect_core_candidates)"
            if [ -z "$CORE_CANDIDATES" ]; then
                warn "Unidentified CPU Schema, cannot be automatically matched Meta Kernel"
                warn "please OpenClash Manually download the matching kernel from the page"
                show_summary
                exit 0
            fi

            RESOLVED_CORE_CHANNEL="$(resolve_core_channel)"
            log "This time we use the core channel: $RESOLVED_CORE_CHANNEL"
            log "candidate Meta Kernel: $CORE_CANDIDATES"
            if download_core "$RESOLVED_CORE_CHANNEL" "$CORE_CANDIDATES"; then
                log "Matching kernel package downloaded: $CHOSEN_CORE_FILE"
                extract_and_install_core
                CORE_CHANGED="1"
            else
                warn "Automatic download ${RESOLVED_CORE_CHANNEL} Kernel failed, please check OpenClash Page manual download"
                show_summary
                exit 0
            fi
            ;;
    esac

    if [ "$PLUGIN_CHANGED" = "1" ] || [ "$CORE_CHANGED" = "1" ]; then
        CHANGED="1"
    else
        CHANGED="0"
    fi

    restart_related_services "$CHANGED"
    show_runtime_versions
    show_summary
}

main "$@"
