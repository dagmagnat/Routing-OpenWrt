#!/bin/sh

set -u

GREEN='\033[32;1m'
YELLOW='\033[33;1m'
NC='\033[0m'

BASE_DIR='/etc/domain-routing'
DNSMASQ_FILE='/etc/dnsmasq.d/90-domain-routing.conf'

log() { printf "$GREEN%s$NC\n" "$*"; }
warn() { printf "$YELLOW%s$NC\n" "$*"; }

find_uci_section() {
    config="$1"
    type="$2"
    name="$3"
    uci show "$config" 2>/dev/null | sed -n "s/^$config\.\(@$type\[[0-9][0-9]*\]\)\.name='$name'.*/\1/p" | head -n 1
}

delete_by_name() {
    config="$1"
    type="$2"
    name="$3"
    while :; do
        sec="$(find_uci_section "$config" "$type" "$name")"
        [ -n "$sec" ] || break
        uci -q delete $config.$sec >/dev/null 2>&1 || break
    done
}

log 'Stopping getdomains'
/etc/init.d/getdomains stop >/dev/null 2>&1 || true
/etc/init.d/getdomains disable >/dev/null 2>&1 || true

log 'Removing init script, cron entry and generated dnsmasq config'
rm -f /etc/init.d/getdomains /etc/hotplug.d/iface/30-vpnroute /etc/hotplug.d/net/30-vpnroute "$DNSMASQ_FILE"
sed -i '/\/etc\/init.d\/getdomains start/d' /etc/crontabs/root 2>/dev/null || true

log 'Removing firewall ipsets/rules/redirects created by domain-routing'
delete_by_name firewall rule mark_domains
delete_by_name firewall rule mark_ip
delete_by_name firewall ipset vpn_domains
delete_by_name firewall ipset vpn_ip
delete_by_name firewall redirect domainrouting_force_dns_udp
delete_by_name firewall redirect domainrouting_force_dns_tcp
uci commit firewall >/dev/null 2>&1 || true

log 'Removing network policy rule mark0x1'
delete_by_name network rule mark0x1
uci commit network >/dev/null 2>&1 || true

if [ "${1:-}" = '--purge' ]; then
    warn 'Purging /etc/domain-routing'
    rm -rf "$BASE_DIR"
else
    warn "Kept $BASE_DIR so your manual domain/IP lists are preserved. Run with --purge to remove them."
fi

/etc/init.d/firewall restart >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
/etc/init.d/network restart >/dev/null 2>&1 || true

log 'Uninstall complete. Tunnel interfaces and firewall zones were intentionally left untouched.'
