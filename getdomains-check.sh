#!/bin/sh

set -u

OK='[OK]'
WARN='[WARN]'
ERR='[ERR]'
BASE_DIR='/etc/domain-routing'
CFG_FILE="$BASE_DIR/config"
DNSMASQ_FILE='/etc/dnsmasq.d/90-domain-routing.conf'
IP_LOAD_FILE='/etc/domain-routing/generated/vpn_ip.lst'
DOMAIN_SET='vpn_domains'
IP_SET='vpn_ip'
NFT_FAMILY='inet'
NFT_TABLE='fw4'

[ -f "$CFG_FILE" ] && . "$CFG_FILE"

check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "$OK command exists: $1"
    else
        echo "$ERR command missing: $1"
    fi
}

check_file() {
    if [ -s "$1" ]; then
        echo "$OK file exists and not empty: $1"
    elif [ -f "$1" ]; then
        echo "$WARN file exists but empty: $1"
    else
        echo "$ERR file missing: $1"
    fi
}

check_uci() {
    config="$1"
    pattern="$2"
    label="$3"
    if uci show "$config" 2>/dev/null | grep -q "$pattern"; then
        echo "$OK $label"
    else
        echo "$ERR missing: $label"
    fi
}

echo 'Domain routing health check'
if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "Firmware: ${PRETTY_NAME:-${OPENWRT_RELEASE:-OpenWrt-like}}"
elif [ -r /etc/openwrt_release ]; then
    . /etc/openwrt_release
    echo "Firmware: ${DISTRIB_DESCRIPTION:-OpenWrt-like}"
else
    echo 'Firmware: unknown OpenWrt-like system'
fi
if command -v apk >/dev/null 2>&1; then
    echo 'Package manager: apk'
elif command -v opkg >/dev/null 2>&1; then
    echo 'Package manager: opkg'
else
    echo 'Package manager: not found'
fi

check_cmd uci
check_cmd dnsmasq
check_cmd nft
check_cmd ip
if [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ]; then
    echo "$OK fw4/firewall4 found"
else
    echo "$WARN fw4/firewall4 command not found; this project expects firewall4/nftables, not legacy fw3/iptables"
fi
if command -v dnsmasq >/dev/null 2>&1 && dnsmasq --help 2>/dev/null | grep -Eq 'nftset|connmark-allowlist'; then
    echo "$OK dnsmasq appears to support nftset"
else
    echo "$WARN dnsmasq nftset support was not detected; install dnsmasq-full or use a firmware build with nftset support"
fi
check_file "$CFG_FILE"
check_file "$DNSMASQ_FILE"
check_file "$IP_LOAD_FILE"

if [ -d "${DOMAINS_DIR:-/etc/domain-routing/domains}" ]; then
    echo "Domain list files: $(find "${DOMAINS_DIR:-/etc/domain-routing/domains}" -type f -name '*.lst' 2>/dev/null | wc -l)"
fi
if [ -d "${IPS_DIR:-/etc/domain-routing/ips}" ]; then
    echo "IPv4/CIDR list files: $(find "${IPS_DIR:-/etc/domain-routing/ips}" -type f -name '*.lst' 2>/dev/null | wc -l)"
fi
if [ -s "$DNSMASQ_FILE" ]; then
    echo "Generated domain rules: $(grep -c '^nftset=/' "$DNSMASQ_FILE" 2>/dev/null || echo 0)"
fi
if [ -s "$IP_LOAD_FILE" ]; then
    echo "Generated IPv4/CIDR entries: $(grep -cv '^[[:space:]]*$' "$IP_LOAD_FILE" 2>/dev/null || echo 0)"
fi

if dnsmasq --conf-file="$DNSMASQ_FILE" --test >/tmp/domain-routing-check-dnsmasq.log 2>&1; then
    echo "$OK dnsmasq generated config syntax"
else
    echo "$ERR dnsmasq generated config syntax failed"
    cat /tmp/domain-routing-check-dnsmasq.log
fi

check_uci dhcp "confdir='${DNSMASQ_DIR:-/etc/dnsmasq.d}'" 'dnsmasq confdir points to persistent directory'
check_uci firewall "name='$DOMAIN_SET'" "firewall set $DOMAIN_SET exists"
check_uci firewall "name='$IP_SET'" "firewall set $IP_SET exists"
check_uci firewall "name='mark_domains'" 'mark_domains rule exists'
check_uci firewall "name='mark_ip'" 'mark_ip rule exists'
check_uci network "name='mark0x1'" 'network policy rule mark0x1 exists'
check_uci firewall "name='domainrouting_force_dns_udp'" 'optional DNS UDP redirect exists'
check_uci firewall "name='domainrouting_force_dns_tcp'" 'optional DNS TCP redirect exists'

if [ "$(uci -q get dhcp.lan.ra 2>/dev/null || true)" = 'disabled' ]; then
    echo "$OK LAN IPv6 RA disabled (IPv4-only routing mode)"
else
    echo "$WARN LAN IPv6 RA is not disabled. IPv6 clients may bypass IPv4 domain routing."
fi

if nft list set "${NFT_FAMILY:-inet}" "${NFT_TABLE:-fw4}" "${DOMAIN_SET:-vpn_domains}" >/tmp/domain-routing-domain-set.log 2>&1; then
    echo "$OK nft set ${DOMAIN_SET:-vpn_domains} exists"
    grep -E 'elements|flags|type' /tmp/domain-routing-domain-set.log | head -5
else
    echo "$WARN nft set ${DOMAIN_SET:-vpn_domains} is not visible yet. Restart firewall/dnsmasq or resolve one listed domain."
fi

if nft list set "${NFT_FAMILY:-inet}" "${NFT_TABLE:-fw4}" "${IP_SET:-vpn_ip}" >/tmp/domain-routing-ip-set.log 2>&1; then
    echo "$OK nft set ${IP_SET:-vpn_ip} exists"
    grep -E 'elements|flags|type' /tmp/domain-routing-ip-set.log | head -5
else
    echo "$WARN nft set ${IP_SET:-vpn_ip} is not visible yet. Restart firewall."
fi

if ip rule show | grep -q 'fwmark 0x1.*lookup vpn\|fwmark 0x1'; then
    echo "$OK ip rule for fwmark 0x1 exists"
else
    echo "$ERR ip rule for fwmark 0x1 missing"
fi

if ip route show table vpn >/tmp/domain-routing-table.log 2>&1 && [ -s /tmp/domain-routing-table.log ]; then
    echo "$OK vpn route table has routes"
    cat /tmp/domain-routing-table.log
else
    echo "$WARN vpn route table is empty. Tunnel may be down or skipped."
fi

if command -v amneziawg >/dev/null 2>&1; then
    echo 'AmneziaWG status:'
    amneziawg show 2>/dev/null || echo "$WARN amneziawg show failed"
elif command -v wg >/dev/null 2>&1; then
    echo 'WireGuard status:'
    wg show 2>/dev/null || echo "$WARN wg show failed"
fi
