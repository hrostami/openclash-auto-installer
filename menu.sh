#!/bin/sh
set -eu

REPO="hrostami/openclash-auto-installer"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"
RESOLVED_BASE_URL=""
TMP_SCRIPT="/tmp/openclash-menu-action.sh"
NONINTERACTIVE_ACTION=""

log() {
    printf '%s\n' "==> $*"
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
  sh menu.sh
  sh menu.sh --check-all-updates
  sh menu.sh --check-updates
  sh menu.sh --check-update-openclash
  sh menu.sh --check-update-passwall
  sh menu.sh --check-update-passwall2
  sh menu.sh --check-update-nikki
  sh menu.sh --check-update-smartdns
  sh menu.sh --check-update-mosdns
  sh menu.sh --openclash
  sh menu.sh --openclash-check-update
  sh menu.sh --openclash-plugin-only
  sh menu.sh --openclash-core-only
  sh menu.sh --openclash-meta-core
  sh menu.sh --openclash-smart-core
  sh menu.sh --passwall
  sh menu.sh --passwall2
  sh menu.sh --nikki
  sh menu.sh --smartdns
  sh menu.sh --mosdns
  sh menu.sh --uninstall-passwall
  sh menu.sh --uninstall-passwall2
  sh menu.sh --uninstall-nikki
  sh menu.sh --uninstall-smartdns
  sh menu.sh --uninstall-mosdns
  sh menu.sh --uninstall-openclash

illustrate:
  Enter the interactive menu without parameters
  When parameters are taken, the corresponding action is executed directly, which is suitable for non-interactive environments.
EOF_USAGE
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --openclash)
                NONINTERACTIVE_ACTION="openclash"
                ;;
            --check-all-updates)
                NONINTERACTIVE_ACTION="check-all-updates"
                ;;
            --check-updates)
                NONINTERACTIVE_ACTION="check-updates"
                ;;
            --check-update-openclash)
                NONINTERACTIVE_ACTION="check-update-openclash"
                ;;
            --check-update-passwall)
                NONINTERACTIVE_ACTION="check-update-passwall"
                ;;
            --check-update-passwall2)
                NONINTERACTIVE_ACTION="check-update-passwall2"
                ;;
            --check-update-nikki)
                NONINTERACTIVE_ACTION="check-update-nikki"
                ;;
            --check-update-smartdns)
                NONINTERACTIVE_ACTION="check-update-smartdns"
                ;;
            --check-update-mosdns)
                NONINTERACTIVE_ACTION="check-update-mosdns"
                ;;
            --openclash-check-update)
                NONINTERACTIVE_ACTION="openclash-check-update"
                ;;
            --openclash-plugin-only)
                NONINTERACTIVE_ACTION="openclash-plugin-only"
                ;;
            --openclash-core-only)
                NONINTERACTIVE_ACTION="openclash-core-only"
                ;;
            --openclash-meta-core)
                NONINTERACTIVE_ACTION="openclash-meta-core"
                ;;
            --openclash-smart-core)
                NONINTERACTIVE_ACTION="openclash-smart-core"
                ;;
            --passwall)
                NONINTERACTIVE_ACTION="passwall"
                ;;
            --passwall2)
                NONINTERACTIVE_ACTION="passwall2"
                ;;
            --nikki)
                NONINTERACTIVE_ACTION="nikki"
                ;;
            --smartdns)
                NONINTERACTIVE_ACTION="smartdns"
                ;;
            --mosdns)
                NONINTERACTIVE_ACTION="mosdns"
                ;;
            --uninstall-passwall)
                NONINTERACTIVE_ACTION="uninstall-passwall"
                ;;
            --uninstall-passwall2)
                NONINTERACTIVE_ACTION="uninstall-passwall2"
                ;;
            --uninstall-nikki)
                NONINTERACTIVE_ACTION="uninstall-nikki"
                ;;
            --uninstall-smartdns)
                NONINTERACTIVE_ACTION="uninstall-smartdns"
                ;;
            --uninstall-mosdns)
                NONINTERACTIVE_ACTION="uninstall-mosdns"
                ;;
            --uninstall-openclash)
                NONINTERACTIVE_ACTION="uninstall-openclash"
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

resolve_base_url() {
    if [ -n "$RESOLVED_BASE_URL" ]; then
        printf '%s' "$RESOLVED_BASE_URL"
        return 0
    fi

    LATEST_SHA="$(curl -fsSL --retry 3 "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null | sed -n 's/.*"sha":[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' | head -n1 || true)"
    if [ -n "$LATEST_SHA" ]; then
        RESOLVED_BASE_URL="https://raw.githubusercontent.com/$REPO/$LATEST_SHA"
    else
        RESOLVED_BASE_URL="$BASE_URL"
    fi

    printf '%s' "$RESOLVED_BASE_URL"
}

download_and_run() {
    SCRIPT_NAME="$1"
    shift || true
    
    # Prefer local smart version
    if [ -f "scripts/$SCRIPT_NAME" ]; then
        log "Use local smart version: scripts/$SCRIPT_NAME"
        sh "scripts/$SCRIPT_NAME" "$@"
        return
    elif [ -f "$SCRIPT_NAME-smart.sh" ]; then
        log "Use local smart version: $SCRIPT_NAME-smart.sh"
        sh "$SCRIPT_NAME-smart.sh" "$@"
        return
    fi
    
    URL="$(resolve_base_url)/$SCRIPT_NAME"

    log "Download script: $URL"
    curl -fsSL --retry 3 "$URL" -o "$TMP_SCRIPT" || die "Download script failed: $SCRIPT_NAME"
    chmod +x "$TMP_SCRIPT"
    sh "$TMP_SCRIPT" "$@"
}

show_menu() {
    cat <<'EOF_MENU'
================ Agent plugin management menu ================
1. Check for plugin updates
2. Install plugin
3. Uninstall plugin
0. quit
==================================================
EOF_MENU
}

show_install_menu() {
    cat <<'EOF_INSTALL_MENU'
================ Install plugin ================
1. Install / renew OpenClash(Automatic recognition Meta / Smart)
2. Update only OpenClash plug-in
3. Install only OpenClash core (auto-recognition Meta / Smart)
4. Install only OpenClash ordinary Meta Kernel
5. Install only OpenClash Smart Meta Kernel
6. Install / renew PassWall
7. Install / renew PassWall2
8. Install / renew Nikki
9. Install / renew SmartDNS
10. Install / renew MosDNS
0. Return to previous level
==========================================
EOF_INSTALL_MENU
}

show_uninstall_menu() {
    cat <<'EOF_UNINSTALL_MENU'
================ Uninstall plugin ================
1. uninstall PassWall
2. uninstall PassWall2
3. uninstall Nikki
4. uninstall SmartDNS
5. uninstall MosDNS
6. uninstall OpenClash
0. Return to previous level
==========================================
EOF_UNINSTALL_MENU
}

show_check_update_menu() {
    cat <<'EOF_CHECK_MENU'
================ Check for plugin updates ================
1. Check all plugins
2. examine OpenClash
3. examine PassWall
4. examine PassWall2
5. examine Nikki
6. examine SmartDNS
7. examine MosDNS
0. Return to previous level
==============================================
EOF_CHECK_MENU
}

read_from_tty() {
    if [ -r /dev/tty ]; then
        read -r "$1" </dev/tty
    else
        die "The current environment is not interactive, please use non-interactive parameter mode instead."
    fi
}

run_action() {
    action="$1"
    case "$action" in
        1|check-updates)
            run_check_update_menu
            SKIP_MAIN_PAUSE="1"
            ;;
        check-all-updates)
            download_and_run check-updates.sh
            ;;
        check-update-openclash)
            download_and_run check-updates.sh --openclash
            ;;
        check-update-passwall)
            download_and_run check-updates.sh --passwall
            ;;
        check-update-passwall2)
            download_and_run check-updates.sh --passwall2
            ;;
        check-update-nikki)
            download_and_run check-updates.sh --nikki
            ;;
        check-update-smartdns)
            download_and_run check-updates.sh --smartdns
            ;;
        check-update-mosdns)
            download_and_run check-updates.sh --mosdns
            ;;
        2|install-plugins)
            run_install_menu
            SKIP_MAIN_PAUSE="1"
            ;;
        3|uninstall-plugins)
            run_uninstall_menu
            SKIP_MAIN_PAUSE="1"
            ;;
        openclash)
            download_and_run install.sh
            ;;
        openclash-check-update)
            download_and_run install.sh --check-update --skip-pkg-update
            ;;
        openclash-plugin-only)
            download_and_run install.sh --plugin-only
            ;;
        openclash-core-only)
            download_and_run install.sh --core-only
            ;;
        openclash-meta-core)
            download_and_run install.sh --core-only --meta-core --skip-pkg-update
            ;;
        openclash-smart-core)
            download_and_run install.sh --core-only --smart-core --skip-pkg-update
            ;;
        passwall)
            download_and_run passwall.sh
            ;;
        passwall2)
            download_and_run passwall2.sh
            ;;
        nikki)
            download_and_run nikki.sh
            ;;
        smartdns)
            download_and_run smartdns.sh
            ;;
        mosdns)
            download_and_run mosdns.sh
            ;;
        uninstall-passwall)
            download_and_run uninstall.sh passwall --delete-config
            ;;
        uninstall-passwall2)
            download_and_run uninstall.sh passwall2 --delete-config
            ;;
        uninstall-nikki)
            download_and_run uninstall.sh nikki --delete-config
            ;;
        uninstall-smartdns)
            download_and_run uninstall.sh smartdns --delete-config
            ;;
        uninstall-mosdns)
            download_and_run uninstall.sh mosdns --delete-config
            ;;
        uninstall-openclash)
            download_and_run uninstall.sh openclash --delete-config
            ;;
        0)
            log "Exited"
            exit 0
            ;;
        *)
            printf '%s\n' '[WARN] Invalid option, please re-enter'
            ;;
    esac
}

run_check_update_menu() {
    while true; do
        show_check_update_menu
        printf 'Please enter options [0-7]: ' >/dev/tty
        read_from_tty subchoice
        case "$subchoice" in
            1)
                download_and_run check-updates.sh
                ;;
            2)
                download_and_run check-updates.sh --openclash
                ;;
            3)
                download_and_run check-updates.sh --passwall
                ;;
            4)
                download_and_run check-updates.sh --passwall2
                ;;
            5)
                download_and_run check-updates.sh --nikki
                ;;
            6)
                download_and_run check-updates.sh --smartdns
                ;;
            7)
                download_and_run check-updates.sh --mosdns
                ;;
            0)
                return 0
                ;;
            *)
                printf '%s\n' '[WARN] Invalid option, please re-enter'
                ;;
        esac
        printf '\nPress Enter to return to the Check Plug-in Updates menu...' >/dev/tty
        read_from_tty _subdummy
        printf '\n'
    done
}

run_install_menu() {
    while true; do
        show_install_menu
        printf 'Please enter options [0-10]: ' >/dev/tty
        read_from_tty subchoice
        case "$subchoice" in
            1)
                download_and_run install.sh
                ;;
            2)
                download_and_run install.sh --plugin-only
                ;;
            3)
                download_and_run install.sh --core-only
                ;;
            4)
                download_and_run install.sh --core-only --meta-core --skip-pkg-update
                ;;
            5)
                download_and_run install.sh --core-only --smart-core --skip-pkg-update
                ;;
            6)
                download_and_run passwall.sh
                ;;
            7)
                download_and_run passwall2.sh
                ;;
            8)
                download_and_run nikki.sh
                ;;
            9)
                download_and_run smartdns.sh
                ;;
            10)
                download_and_run mosdns.sh
                ;;
            0)
                return 0
                ;;
            *)
                printf '%s\n' '[WARN] Invalid option, please re-enter'
                ;;
        esac
        printf '\nPress Enter to return to the plug-in installation menu...' >/dev/tty
        read_from_tty _subdummy
        printf '\n'
    done
}

run_uninstall_menu() {
    while true; do
        show_uninstall_menu
        printf 'Please enter options [0-6]: ' >/dev/tty
        read_from_tty subchoice
        case "$subchoice" in
            1)
                download_and_run uninstall.sh passwall --delete-config
                ;;
            2)
                download_and_run uninstall.sh passwall2 --delete-config
                ;;
            3)
                download_and_run uninstall.sh nikki --delete-config
                ;;
            4)
                download_and_run uninstall.sh smartdns --delete-config
                ;;
            5)
                download_and_run uninstall.sh mosdns --delete-config
                ;;
            6)
                download_and_run uninstall.sh openclash --delete-config
                ;;
            0)
                return 0
                ;;
            *)
                printf '%s\n' '[WARN] Invalid option, please re-enter'
                ;;
        esac
        printf '\nPress Enter to return to the uninstall plug-in menu...' >/dev/tty
        read_from_tty _subdummy
        printf '\n'
    done
}

main() {
    parse_args "$@"
    need_cmd curl

    if [ -n "$NONINTERACTIVE_ACTION" ]; then
        run_action "$NONINTERACTIVE_ACTION"
        exit 0
    fi

    while true; do
        show_menu
        printf 'Please enter options [0-3]: ' >/dev/tty
        read_from_tty choice
        SKIP_MAIN_PAUSE="0"
        run_action "$choice"
        if [ "$SKIP_MAIN_PAUSE" != "1" ]; then
            printf '\nPress the Enter key to return to the menu...' >/dev/tty
            read_from_tty _dummy
            printf '\n'
        fi
    done
}

main "$@"
