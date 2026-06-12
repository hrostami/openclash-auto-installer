#!/bin/sh
set -eu

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

ensure_dir() {
    [ -d "$1" ] || mkdir -p "$1"
}

fix_core_permissions() {
    if [ -f /etc/openclash/core/clash_meta ]; then
        chmod 0755 /etc/openclash/core/clash_meta || warn "repair clash_meta Permission failed"
        log "Checked and fixed clash_meta Permissions"
    else
        warn "not found /etc/openclash/core/clash_meta"
    fi
}

restart_services() {
    if [ -x /etc/init.d/openclash ]; then
        /etc/init.d/openclash restart >/dev/null 2>&1 || warn "OpenClash Service restart failed"
        log "Tried restarting OpenClash"
    fi

    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart >/dev/null 2>&1 || warn "uhttpd Restart failed"
        log "Tried restarting uhttpd"
    fi
}

refresh_index() {
    PKG_MGR="$1"
    case "$PKG_MGR" in
        opkg)
            log "refresh opkg Software source"
            opkg update || warn "opkg update fail"
            ;;
        apk)
            log "refresh apk Software source"
            apk update || warn "apk update fail"
            ;;
    esac
}

show_status() {
    PKG_MGR="$1"
    log "System package manager: $PKG_MGR"

    if [ -f /etc/openclash/core/clash_meta ]; then
        log "detected Meta Kernel: /etc/openclash/core/clash_meta"
    else
        warn "not detected Meta kernel file"
    fi

    if [ "$PKG_MGR" = "opkg" ]; then
        VER="$(opkg status luci-app-openclash 2>/dev/null | sed -n 's/^Version: //p' | head -n1 || true)"
    else
        VER="$(apk info -a luci-app-openclash 2>/dev/null | sed -n 's/^version: //p' | head -n1 || true)"
    fi

    log "current OpenClash Version: ${VER:-unknown or not installed}"
}

main() {
    PKG_MGR="$(detect_pkg_mgr)"

    log "Start execution OpenClash Repair process"
    ensure_dir /etc/openclash
    ensure_dir /etc/openclash/core

    refresh_index "$PKG_MGR"
    fix_core_permissions
    restart_services
    show_status "$PKG_MGR"

    log "Repair process completed"
}

main "$@"
