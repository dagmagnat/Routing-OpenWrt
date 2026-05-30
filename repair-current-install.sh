#!/bin/sh
# Repair helper for existing Domain Routing installs.
# It copies bundled route lists, converts WG/AWG addresses/allowed_ips to UCI list fields,
# regenerates dnsmasq/nftset files, and restarts services.

set -u

BASE_DIR="${BASE_DIR:-/etc/domain-routing}"
DOMAINS_DIR="$BASE_DIR/domains"
IPS_DIR="$BASE_DIR/ips"
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd -P || pwd)"
PROJECT_LIST_DIR="${PROJECT_LIST_DIR:-$SCRIPT_DIR/domains}"

log() { printf '\033[32;1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33;1m%s\033[0m\n' "$*"; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }
normalize_list_value() { printf '%s' "$1" | sed 's/,/ /g;s/[[:space:]][[:space:]]*/ /g;s/^[[:space:]]*//;s/[[:space:]]*$//'; }

copy_bundled_lists() {
    mkdir -p "$DOMAINS_DIR" "$IPS_DIR"
    [ -d "$PROJECT_LIST_DIR" ] || { warn "Папка bundled-списков не найдена: $PROJECT_LIST_DIR"; return 0; }
    for src_file in "$PROJECT_LIST_DIR"/*.lst; do
        [ -f "$src_file" ] || continue
        base="$(basename "$src_file")"
        first_data_line="$(sed -n '/^[[:space:]]*#/d;/^[[:space:]]*$/d;{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' "$src_file" 2>/dev/null || true)"
        if printf '%s\n' "$base $first_data_line" | grep -Eiq '(^|[ _.-])ip([ _.-]|$)|^[^ ]* [0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$'; then
            dst_file="$IPS_DIR/$base"
        else
            dst_file="$DOMAINS_DIR/$base"
        fi
        if [ ! -f "$dst_file" ]; then
            cp "$src_file" "$dst_file" && log "copied: $dst_file"
        else
            warn "exists, not overwritten: $dst_file"
        fi
    done
}

convert_list_option() {
    section="$1"
    option="$2"
    raw="$(uci -q get "network.$section.$option" 2>/dev/null || true)"
    [ -n "$raw" ] || return 0
    values="$(normalize_list_value "$raw")"
    [ -n "$values" ] || return 0
    uci -q delete "network.$section.$option" >/dev/null 2>&1 || true
    for item in $values; do
        uci add_list "network.$section.$option=$item" || return 1
    done
    log "converted network.$section.$option to UCI list: $values"
}

convert_wg_awg_lists() {
    cmd_exists uci || { warn 'uci не найден'; return 1; }

    # Named interfaces: wg0/awg0/etc.
    for section in $(uci -q show network | sed -n "s/^network\.\([^.=]*\)=interface$/\1/p"); do
        proto="$(uci -q get network.$section.proto 2>/dev/null || true)"
        case "$proto" in
            wireguard|amneziawg)
                convert_list_option "$section" addresses || true
                ;;
        esac
    done

    # Anonymous and named peer sections with allowed_ips.
    uci -q show network | sed -n "s/^network\.\([^=]*\)\.allowed_ips=.*/\1/p" | sort -u | while IFS= read -r section; do
        [ -n "$section" ] || continue
        convert_list_option "$section" allowed_ips || true
    done

    uci commit network
}

restart_stack() {
    if [ -x /etc/init.d/getdomains ]; then
        /etc/init.d/getdomains restart || warn 'getdomains restart failed'
    else
        warn '/etc/init.d/getdomains не найден'
    fi
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || warn 'dnsmasq restart failed'
    /etc/init.d/firewall restart >/dev/null 2>&1 || warn 'firewall restart failed'
    if [ "${NO_NETWORK_RESTART:-0}" != '1' ]; then
        warn 'Перезапускаю network. SSH может кратко оборваться.'
        /etc/init.d/network restart >/dev/null 2>&1 || warn 'network restart failed'
    else
        warn 'NO_NETWORK_RESTART=1: network не перезапускался. Перезапустите интерфейс вручную.'
    fi
}

main() {
    copy_bundled_lists
    convert_wg_awg_lists
    restart_stack
    log 'Repair completed. Run: sh getdomains-check.sh'
}

main "$@"
