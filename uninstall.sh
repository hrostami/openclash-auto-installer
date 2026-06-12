#!/bin/sh
set -eu

TARGET="${1:-}"
DELETE_CONFIG=0

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

detect_pkg_mgr() {
    if command -v opkg >/dev/null 2>&1; then
        printf 'opkg'
    elif command -v apk >/dev/null 2>&1; then
        printf 'apk'
    else
        die "not detected opkg or apk, the current system does not support it yet"
    fi
}

pkg_installed() {
    PKG_MGR="$1"
    PKG="$2"

    case "$PKG_MGR" in
        opkg)
            opkg list-installed 2>/dev/null | grep -q "^$PKG - "
            ;;
        apk)
            apk info -e "$PKG" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

remove_pkg_if_installed() {
    PKG_MGR="$1"
    PKG="$2"
    MANUAL_CMD=""

    if ! pkg_installed "$PKG_MGR" "$PKG"; then
        log "Not installed $PKG,jump over"
        return 0
    fi

    case "$PKG_MGR" in
        opkg)
            MANUAL_CMD="opkg remove $PKG"
            if ! OUTPUT="$(opkg remove "$PKG" 2>&1)"; then
                printf '%s\n' "$OUTPUT"
                warn "Remove $PKG fail"
            else
                printf '%s\n' "$OUTPUT"
            fi
            ;;
        apk)
            MANUAL_CMD="apk del $PKG"
            apk del "$PKG" || warn "Remove $PKG fail"
            ;;
    esac

    if pkg_installed "$PKG_MGR" "$PKG"; then
        die "$PKG The uninstallation is still not successful, please check the dependencies or perform it manually.: $MANUAL_CMD"
    fi
}

remove_paths() {
    for path in "$@"; do
        rm -rf "$path" 2>/dev/null || true
    done
}

stop_disable_service() {
    SVC="$1"

    if [ -x "/etc/init.d/$SVC" ]; then
        /etc/init.d/"$SVC" stop >/dev/null 2>&1 || true
        /etc/init.d/"$SVC" disable >/dev/null 2>&1 || true
        log "Service stopped and disabled: $SVC"
    else
        log "Service script not found: $SVC,jump over"
    fi
}

refresh_web() {
    remove_paths \
        /tmp/luci-* \
        /tmp/.luci* \
        /tmp/etc/config/ucitrack \
        /var/run/luci-indexcache

    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd restart >/dev/null 2>&1 || warn "rpcd Restart failed"
    fi

    warn "Please refresh the page or switch the left menu once, the plug-in entrance will be updated automatically; if it still does not take effect, log in again LuCI"
}

remove_openclash_core() {
    if [ -f /etc/openclash/core/clash_meta ]; then
        rm -f /etc/openclash/core/clash_meta
        log "Deleted /etc/openclash/core/clash_meta"
    else
        warn "not found clash_meta Kernel file, skip"
    fi
}

safe_uninstall_passwall() {
    PKG_MGR="$1"
    log "Start safe uninstallation PassWall(Only uninstall the main package)"

    stop_disable_service passwall
    remove_pkg_if_installed "$PKG_MGR" luci-i18n-passwall-zh-cn
    remove_pkg_if_installed "$PKG_MGR" luci-app-passwall

    if [ "$DELETE_CONFIG" -eq 1 ]; then
        log "delete PassWall Configuration file"
        remove_paths /etc/config/passwall
    else
        warn "Keep by default /etc/config/passwall Configuration file"
    fi

    log "PassWall Safe uninstall complete"
}

safe_uninstall_passwall2() {
    PKG_MGR="$1"
    log "Start safe uninstallation PassWall2(Only uninstall the main package)"

    stop_disable_service passwall2
    remove_pkg_if_installed "$PKG_MGR" luci-i18n-passwall2-zh-cn
    remove_pkg_if_installed "$PKG_MGR" luci-app-passwall2

    if [ "$DELETE_CONFIG" -eq 1 ]; then
        log "delete PassWall2 Configuration file"
        remove_paths /etc/config/passwall2
    else
        warn "Keep by default /etc/config/passwall2 Configuration file"
    fi

    log "PassWall2 Safe uninstall complete"
}

safe_uninstall_nikki() {
    PKG_MGR="$1"
    log "Start safe uninstallation Nikki(Only uninstall the main package)"

    stop_disable_service nikki
    remove_pkg_if_installed "$PKG_MGR" luci-i18n-nikki-zh-cn
    remove_pkg_if_installed "$PKG_MGR" luci-app-nikki
    remove_pkg_if_installed "$PKG_MGR" nikki
    remove_pkg_if_installed "$PKG_MGR" mihomo-meta

    if [ "$DELETE_CONFIG" -eq 1 ]; then
        log "delete Nikki Configuration file"
        remove_paths /etc/config/nikki
    else
        warn "Keep by default /etc/config/nikki Configuration file"
    fi

    log "Nikki Safe uninstall complete"
}

safe_uninstall_smartdns() {
    PKG_MGR="$1"
    log "Start safe uninstallation SmartDNS(Only uninstall the main package)"

    stop_disable_service smartdns
    remove_pkg_if_installed "$PKG_MGR" app-meta-smartdns
    remove_pkg_if_installed "$PKG_MGR" luci-i18n-smartdns-zh-cn
    remove_pkg_if_installed "$PKG_MGR" luci-app-smartdns
    remove_pkg_if_installed "$PKG_MGR" smartdns

    if [ "$DELETE_CONFIG" -eq 1 ]; then
        log "delete SmartDNS Configuration file"
        remove_paths /etc/config/smartdns
    else
        warn "Keep by default /etc/config/smartdns Configuration file"
    fi

    log "SmartDNS Safe uninstall complete"
}

safe_uninstall_mosdns() {
    PKG_MGR="$1"
    log "Start safe uninstallation MosDNS(Only uninstall the main package)"

    stop_disable_service mosdns
    remove_pkg_if_installed "$PKG_MGR" luci-i18n-mosdns-zh-cn
    remove_pkg_if_installed "$PKG_MGR" luci-app-mosdns
    remove_pkg_if_installed "$PKG_MGR" mosdns

    if [ "$DELETE_CONFIG" -eq 1 ]; then
        log "delete MosDNS Configuration file"
        remove_paths /etc/config/mosdns /etc/mosdns
    else
        warn "Keep by default /etc/config/mosdns and /etc/mosdns Configuration file"
    fi

    log "MosDNS Safe uninstall complete"
}

safe_uninstall_openclash() {
    PKG_MGR="$1"
    log "Start safe uninstallation OpenClash(Only uninstall the main package)"

    stop_disable_service openclash
    remove_pkg_if_installed "$PKG_MGR" luci-app-openclash
    remove_openclash_core

    if [ "$DELETE_CONFIG" -eq 1 ]; then
        log "delete OpenClash Configuration directory"
        remove_paths /etc/config/openclash /etc/openclash
    else
        warn "Keep by default /etc/openclash Configure directories to avoid accidentally deleting subscriptions and configurations"
    fi

    log "OpenClash Safe uninstall complete"
}

usage() {
    cat <<'EOF_USAGE'
usage:
  sh uninstall.sh passwall [--delete-config]
  sh uninstall.sh passwall2 [--delete-config]
  sh uninstall.sh nikki [--delete-config]
  sh uninstall.sh smartdns [--delete-config]
  sh uninstall.sh mosdns [--delete-config]
  sh uninstall.sh openclash [--delete-config]

illustrate:
  By default, safe uninstallation is performed, only the main package is removed, and shared dependencies are left unchanged.
  --delete-config The configuration file of the corresponding plug-in will be additionally deleted.
EOF_USAGE
}

parse_args() {
    [ -n "$TARGET" ] || {
        usage
        exit 1
    }

    shift || true
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --delete-config)
                DELETE_CONFIG=1
                ;;
            -h|--help|help)
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

main() {
    parse_args "$@"
    PKG_MGR="$(detect_pkg_mgr)"
    log "Package manager detected: $PKG_MGR"

    case "$TARGET" in
        passwall)
            safe_uninstall_passwall "$PKG_MGR"
            ;;
        passwall2)
            safe_uninstall_passwall2 "$PKG_MGR"
            ;;
        nikki)
            safe_uninstall_nikki "$PKG_MGR"
            ;;
        smartdns)
            safe_uninstall_smartdns "$PKG_MGR"
            ;;
        mosdns)
            safe_uninstall_mosdns "$PKG_MGR"
            ;;
        openclash)
            safe_uninstall_openclash "$PKG_MGR"
            ;;
        *)
            die "Unsupported safe uninstall target: $TARGET"
            ;;
    esac

    refresh_web
    log "Safe uninstall process completed"
}

main "$@"
