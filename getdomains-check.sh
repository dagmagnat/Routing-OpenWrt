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
. /etc/os-release 2>/dev/null || true
echo "OpenWrt: ${OPENWRT_RELEASE:-unknown}"

check_cmd dnsmasq
check_cmd nft
check_cmd ip
check_file "$CFG_FILE"
check_file "$DNSMASQ_FILE"
check_file "$IP_LOAD_FILE"

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
