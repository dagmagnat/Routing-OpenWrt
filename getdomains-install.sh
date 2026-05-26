#!/bin/sh

# Domain routing for OpenWrt 23/24/25.
# Main target: OpenWrt 24.10 and 25.12 with fw4/nftables and dnsmasq-full nftset.

set -u

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
YELLOW='\033[33;1m'
NC='\033[0m'

BASE_DIR='/etc/domain-routing'
DOMAINS_DIR="$BASE_DIR/domains"
IPS_DIR="$BASE_DIR/ips"
GEN_DIR="$BASE_DIR/generated"
DNSMASQ_DIR='/etc/dnsmasq.d'
DNSMASQ_FILE="$DNSMASQ_DIR/90-domain-routing.conf"
IP_LOAD_FILE="$GEN_DIR/vpn_ip.lst"
CFG_FILE="$BASE_DIR/config"
UPDATE_SCRIPT="$BASE_DIR/getdomains-update.sh"
CONVERTER_SCRIPT="$BASE_DIR/singbox-convert.sh"
SINGBOX_SOURCE_DIR="$BASE_DIR/singbox"
PROJECT_RAW_BASE="${PROJECT_RAW_BASE:-https://raw.githubusercontent.com/dagmagnat/domain-routing-openwrt/main}"
INIT_SCRIPT='/etc/init.d/getdomains'
TABLE_NAME='vpn'
TABLE_ID='99'
MARK='0x1'
DOMAIN_SET='vpn_domains'
IP_SET='vpn_ip'
NFT_FAMILY='inet'
NFT_TABLE='fw4'
CRON_LINE='17 */8 * * * /etc/init.d/getdomains start >/tmp/getdomains.log 2>&1'

log() { printf "$GREEN%s$NC\n" "$*"; }
warn() { printf "$YELLOW%s$NC\n" "$*"; }
err() { printf "$RED%s$NC\n" "$*"; }
die() { err "$*"; exit 1; }

read_default() {
    prompt="$1"
    default="$2"
    printf "%s [%s]:\n" "$prompt" "$default"
    IFS= read -r answer || answer=''
    if [ -z "$answer" ]; then
        printf '%s' "$default"
    else
        printf '%s' "$answer"
    fi
}

read_secret() {
    prompt="$1"
    printf "%s\n" "$prompt"
    IFS= read -r answer || answer=''
    printf '%s' "$answer"
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

fetch_url() {
    url="$1"
    out="$2"
    if cmd_exists curl; then
        curl -4 -fsSL --connect-timeout 10 --max-time 40 --retry 2 -o "$out" "$url"
    else
        wget -4 -q -T 40 -O "$out" "$url"
    fi
}

pkg_manager() {
    if cmd_exists apk; then
        printf 'apk'
    elif cmd_exists opkg; then
        printf 'opkg'
    else
        printf 'none'
    fi
}

pkg_update() {
    pm="$(pkg_manager)"
    if [ "$pm" = 'apk' ]; then
        apk update
    elif [ "$pm" = 'opkg' ]; then
        opkg update
    else
        die 'Neither apk nor opkg was found'
    fi
}

pkg_installed() {
    package="$1"
    pm="$(pkg_manager)"
    if [ "$pm" = 'apk' ]; then
        apk info -e "$package" >/dev/null 2>&1 || apk list -I "$package" 2>/dev/null | grep -q "^$package-"
    elif [ "$pm" = 'opkg' ]; then
        opkg list-installed "$package" 2>/dev/null | grep -q "^$package " || opkg list-installed 2>/dev/null | grep -q "^$package "
    else
        return 1
    fi
}

pkg_install() {
    package="$1"
    if pkg_installed "$package"; then
        log "$package already installed"
        return 0
    fi

    pm="$(pkg_manager)"
    log "Installing $package"
    if [ "$pm" = 'apk' ]; then
        apk add "$package"
    elif [ "$pm" = 'opkg' ]; then
        opkg install "$package"
    else
        die 'Neither apk nor opkg was found'
    fi
}

install_dnsmasq_full() {
    if pkg_installed dnsmasq-full; then
        log 'dnsmasq-full already installed'
        return 0
    fi

    pm="$(pkg_manager)"
    if [ "$pm" = 'apk' ]; then
        log 'Installing dnsmasq-full via apk'
        apk add dnsmasq-full || die 'Failed to install dnsmasq-full'
    else
        log 'Installing dnsmasq-full via opkg'
        opkg update || die 'opkg update failed'
        cd /tmp || die 'Cannot enter /tmp'
        rm -f /tmp/dnsmasq-full*.ipk
        opkg download dnsmasq-full || die 'Failed to download dnsmasq-full'
        opkg remove dnsmasq >/dev/null 2>&1 || true
        opkg install /tmp/dnsmasq-full*.ipk || opkg install dnsmasq-full || die 'Failed to install dnsmasq-full'
        [ -f /etc/config/dhcp-opkg ] && cp /etc/config/dhcp /etc/config/dhcp-old && mv /etc/config/dhcp-opkg /etc/config/dhcp
    fi
}

check_system() {
    [ -r /etc/os-release ] || die '/etc/os-release not found. This script is intended for OpenWrt.'
    . /etc/os-release
    version_id="${VERSION_ID:-0}"
    major="${version_id%%.*}"
    [ -n "$major" ] || major=0

    model='unknown'
    [ -r /tmp/sysinfo/model ] && model="$(cat /tmp/sysinfo/model)"
    printf "$BLUE%s$NC\n" "Model: $model"
    printf "$BLUE%s$NC\n" "OpenWrt: ${OPENWRT_RELEASE:-$version_id}"

    case "$major" in
        23|24|25) : ;;
        *) die 'Supported releases are OpenWrt 23.05, 24.10 and 25.12. For your request the main target is 24/25.' ;;
    esac

    if [ "$major" -lt 22 ]; then
        die 'fw4/nftables mode requires OpenWrt 22.03 or newer.'
    fi
}

ensure_directories() {
    mkdir -p "$BASE_DIR" "$DOMAINS_DIR" "$IPS_DIR" "$GEN_DIR" "$DNSMASQ_DIR" /etc/hotplug.d/iface /etc/hotplug.d/net /etc/iproute2
}

seed_lists() {
    if [ ! -f "$DOMAINS_DIR/10-youtube.lst" ]; then
        cat > "$DOMAINS_DIR/10-youtube.lst" <<'LIST'
# One domain per line. Subdomains are matched automatically by dnsmasq.
youtube.com
youtubei.googleapis.com
ytimg.com
googlevideo.com
ggpht.com
googleapis.com
googleusercontent.com
youtubekids.com
LIST
    fi

    if [ ! -f "$DOMAINS_DIR/20-instagram-meta.lst" ]; then
        cat > "$DOMAINS_DIR/20-instagram-meta.lst" <<'LIST'
# Examples. Remove or extend as needed.
instagram.com
cdninstagram.com
facebook.com
fbcdn.net
fbsbx.com
messenger.com
threads.net
whatsapp.com
whatsapp.net
LIST
    fi

    if [ ! -f "$IPS_DIR/README.txt" ]; then
        cat > "$IPS_DIR/README.txt" <<'LIST'
Put custom IPv4 addresses and CIDR networks here, one entry per line.
Examples:
# Telegram or WhatsApp IP ranges may be placed in files like:
# /etc/domain-routing/ips/10-telegram.lst
# /etc/domain-routing/ips/20-whatsapp.lst

Comments starting with # and empty lines are ignored.
LIST
    fi

    [ -f "$IPS_DIR/10-telegram.lst" ] || printf '# Add Telegram IPv4/CIDR ranges here\n' > "$IPS_DIR/10-telegram.lst"
    [ -f "$IPS_DIR/20-whatsapp.lst" ] || printf '# Add WhatsApp IPv4/CIDR ranges here\n' > "$IPS_DIR/20-whatsapp.lst"
}

select_domain_source() {
    echo 'Choose remote domain list source:'
    echo '1) Custom local lists only [recommended until you provide your own list]'
    echo '2) Russia inside list from itdoginfo/allow-domains'
    echo '3) Russia outside list from itdoginfo/allow-domains'
    echo '4) Ukraine list from itdoginfo/allow-domains'
    echo '5) My own raw dnsmasq/nftset URL'
    echo '6) Disable remote list'
    while true; do
        IFS= read -r choice || choice='1'
        case "$choice" in
            ''|1)
                USE_REMOTE_DOMAINS='0'
                REMOTE_DOMAINS_URL=''
                break
                ;;
            2)
                USE_REMOTE_DOMAINS='1'
                REMOTE_DOMAINS_URL='https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/inside-dnsmasq-nfset.lst'
                break
                ;;
            3)
                USE_REMOTE_DOMAINS='1'
                REMOTE_DOMAINS_URL='https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/outside-dnsmasq-nfset.lst'
                break
                ;;
            4)
                USE_REMOTE_DOMAINS='1'
                REMOTE_DOMAINS_URL='https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Ukraine/inside-dnsmasq-nfset.lst'
                break
                ;;
            5)
                USE_REMOTE_DOMAINS='1'
                REMOTE_DOMAINS_URL="$(read_secret 'Enter raw URL with dnsmasq nftset rules:')"
                break
                ;;
            6)
                USE_REMOTE_DOMAINS='0'
                REMOTE_DOMAINS_URL=''
                break
                ;;
            *) echo 'Choose 1-6' ;;
        esac
    done
}

write_config() {
    cat > "$CFG_FILE" <<EOF_CFG
# Domain routing configuration.
# Edit this file manually, then run: /etc/init.d/getdomains start

DOMAIN_SET="$DOMAIN_SET"
IP_SET="$IP_SET"
MARK="$MARK"
NFT_FAMILY="$NFT_FAMILY"
NFT_TABLE="$NFT_TABLE"
DNSMASQ_DIR="$DNSMASQ_DIR"
DNSMASQ_FILE="$DNSMASQ_FILE"
IP_LOAD_FILE="$IP_LOAD_FILE"
DOMAINS_DIR="$DOMAINS_DIR"
IPS_DIR="$IPS_DIR"
GEN_DIR="$GEN_DIR"

# Remote dnsmasq/nftset list. Keep disabled for fully local/manual control.
USE_REMOTE_DOMAINS="$USE_REMOTE_DOMAINS"
REMOTE_DOMAINS_URL="$REMOTE_DOMAINS_URL"

# Optional remote IPv4/CIDR raw lists, separated by spaces.
# Example: REMOTE_IP_URLS="https://example.com/telegram.lst https://example.com/whatsapp.lst"
REMOTE_IP_URLS=""
EOF_CFG
}

find_uci_section() {
    config="$1"
    type="$2"
    name="$3"
    uci show "$config" 2>/dev/null | sed -n "s/^$config\.\(@$type\[[0-9][0-9]*\]\)\.name='$name'.*/\1/p" | head -n 1
}

ensure_rt_table() {
    grep -Eq "^$TABLE_ID[[:space:]]+$TABLE_NAME$" /etc/iproute2/rt_tables 2>/dev/null || echo "$TABLE_ID $TABLE_NAME" >> /etc/iproute2/rt_tables
}

ensure_network_mark_rule() {
    sec="$(find_uci_section network rule mark0x1)"
    if [ -z "$sec" ]; then
        uci add network rule >/dev/null
        sec='@rule[-1]'
        uci set network.$sec.name='mark0x1'
    fi
    uci set network.$sec.mark="$MARK"
    uci set network.$sec.priority='100'
    uci set network.$sec.lookup="$TABLE_NAME"
    uci commit network
}

ensure_hotplug_route() {
    dev="$1"
    cat > /etc/hotplug.d/iface/30-vpnroute <<EOF_ROUTE
#!/bin/sh

[ "\$ACTION" = 'ifup' ] || [ "\$ACTION" = 'ifupdate' ] || [ "\$ACTION" = 'iflink' ] || exit 0
ip route replace table $TABLE_NAME default dev $dev 2>/dev/null || true
EOF_ROUTE
    chmod +x /etc/hotplug.d/iface/30-vpnroute
    cp /etc/hotplug.d/iface/30-vpnroute /etc/hotplug.d/net/30-vpnroute
    ip route replace table "$TABLE_NAME" default dev "$dev" 2>/dev/null || true
}

ensure_firewall_ipset() {
    set_name="$1"
    loadfile="${2:-}"
    sec="$(find_uci_section firewall ipset "$set_name")"
    if [ -z "$sec" ]; then
        uci add firewall ipset >/dev/null
        sec='@ipset[-1]'
        uci set firewall.$sec.name="$set_name"
    fi
    uci set firewall.$sec.match='dst_net'
    if [ -n "$loadfile" ]; then
        uci set firewall.$sec.loadfile="$loadfile"
    else
        uci -q delete firewall.$sec.loadfile >/dev/null 2>&1 || true
    fi
}

ensure_firewall_mark_rule() {
    rule_name="$1"
    set_name="$2"
    sec="$(find_uci_section firewall rule "$rule_name")"
    if [ -z "$sec" ]; then
        uci add firewall rule >/dev/null
        sec='@rule[-1]'
        uci set firewall.$sec.name="$rule_name"
    fi
    uci set firewall.$sec.src='lan'
    uci set firewall.$sec.dest='*'
    uci set firewall.$sec.proto='all'
    uci set firewall.$sec.ipset="$set_name"
    uci set firewall.$sec.set_mark="$MARK"
    uci set firewall.$sec.target='MARK'
    uci set firewall.$sec.family='ipv4'
}

ensure_firewall_zone() {
    zone="$1"
    network="$2"
    device="$3"
    input_policy="$4"

    [ "$zone" = '0' ] && return 0

    sec="$(find_uci_section firewall zone "$zone")"
    if [ -z "$sec" ]; then
        uci add firewall zone >/dev/null
        sec='@zone[-1]'
        uci set firewall.$sec.name="$zone"
    fi
    uci -q delete firewall.$sec.network >/dev/null 2>&1 || true
    uci -q delete firewall.$sec.device >/dev/null 2>&1 || true
    [ -n "$network" ] && uci set firewall.$sec.network="$network"
    [ -n "$device" ] && uci set firewall.$sec.device="$device"
    uci set firewall.$sec.forward='REJECT'
    uci set firewall.$sec.output='ACCEPT'
    uci set firewall.$sec.input="$input_policy"
    uci set firewall.$sec.masq='1'
    uci set firewall.$sec.mtu_fix='1'
    uci set firewall.$sec.family='ipv4'

    fwd="$(find_uci_section firewall forwarding "$zone-lan")"
    if [ -z "$fwd" ]; then
        uci add firewall forwarding >/dev/null
        fwd='@forwarding[-1]'
        uci set firewall.$fwd.name="$zone-lan"
    fi
    uci set firewall.$fwd.src='lan'
    uci set firewall.$fwd.dest="$zone"
    uci set firewall.$fwd.family='ipv4'
}

ensure_firewall() {
    ensure_firewall_ipset "$DOMAIN_SET" ''
    ensure_firewall_mark_rule 'mark_domains' "$DOMAIN_SET"
    ensure_firewall_ipset "$IP_SET" "$IP_LOAD_FILE"
    ensure_firewall_mark_rule 'mark_ip' "$IP_SET"
    uci commit firewall
}

ensure_dnsmasq_confdir() {
    current="$(uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null || true)"
    if [ "$current" != "$DNSMASQ_DIR" ]; then
        uci set dhcp.@dnsmasq[0].confdir="$DNSMASQ_DIR"
        uci commit dhcp
    fi
}

install_wireguard() {
    pkg_install wireguard-tools
}

install_awg_packages() {
    if pkg_installed amneziawg-tools; then
        log 'amneziawg-tools already installed'
        return 0
    fi

    url='https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh'
    tmp='/tmp/amneziawg-install.sh'
    log 'Installing AmneziaWG packages via Slava-Shchipunov/awg-openwrt installer'
    if fetch_url "$url" "$tmp"; then
        chmod +x "$tmp"
        # -en: non-interactive package installation mode from upstream installer.
        sh "$tmp" -en || warn 'AmneziaWG upstream installer returned an error. You may need to install AWG packages manually.'
    else
        warn 'Failed to download AmneziaWG installer. Install AWG packages manually and run this script again.'
    fi
}

configure_wg_interface() {
    iface="$1"
    peer_type="$2"

    if [ "$peer_type" = 'awg' ]; then
        install_awg_packages
        proto='amneziawg'
        peer_section="amneziawg_$iface"
    else
        install_wireguard
        proto='wireguard'
        peer_section="wireguard_$iface"
    fi

    private_key="$(read_secret 'Enter PrivateKey from [Interface]:')"
    address="$(read_default 'Enter Address with subnet, for example 10.8.0.2/32 or 192.168.100.5/24' '10.8.0.2/32')"

    uci set network.$iface=interface
    uci set network.$iface.proto="$proto"
    uci set network.$iface.private_key="$private_key"
    uci set network.$iface.addresses="$address"
    uci set network.$iface.listen_port='51820'

    if [ "$peer_type" = 'awg' ]; then
        awg_jc="$(read_default 'Enter Jc' '3')"
        awg_jmin="$(read_default 'Enter Jmin' '10')"
        awg_jmax="$(read_default 'Enter Jmax' '50')"
        awg_s1="$(read_secret 'Enter S1:')"
        awg_s2="$(read_secret 'Enter S2:')"
        awg_h1="$(read_secret 'Enter H1:')"
        awg_h2="$(read_secret 'Enter H2:')"
        awg_h3="$(read_secret 'Enter H3:')"
        awg_h4="$(read_secret 'Enter H4:')"
        uci set network.$iface.awg_jc="$awg_jc"
        uci set network.$iface.awg_jmin="$awg_jmin"
        uci set network.$iface.awg_jmax="$awg_jmax"
        uci set network.$iface.awg_s1="$awg_s1"
        uci set network.$iface.awg_s2="$awg_s2"
        uci set network.$iface.awg_h1="$awg_h1"
        uci set network.$iface.awg_h2="$awg_h2"
        uci set network.$iface.awg_h3="$awg_h3"
        uci set network.$iface.awg_h4="$awg_h4"
    fi

    public_key="$(read_secret 'Enter PublicKey from [Peer]:')"
    preshared_key="$(read_secret 'Enter PresharedKey from [Peer] or leave empty:')"
    endpoint_host="$(read_secret 'Enter Endpoint host without port:')"
    endpoint_port="$(read_default 'Enter Endpoint port' '51820')"

    if ! uci show network 2>/dev/null | grep -q "=\'$peer_section\'"; then
        uci add network "$peer_section" >/dev/null
    fi
    uci set network.@$peer_section[0]=${peer_section}
    uci set network.@$peer_section[0].name="${iface}_client"
    uci set network.@$peer_section[0].public_key="$public_key"
    if [ -n "$preshared_key" ]; then
        uci set network.@$peer_section[0].preshared_key="$preshared_key"
    else
        uci -q delete network.@$peer_section[0].preshared_key >/dev/null 2>&1 || true
    fi
    uci set network.@$peer_section[0].route_allowed_ips='0'
    uci set network.@$peer_section[0].persistent_keepalive='25'
    uci set network.@$peer_section[0].endpoint_host="$endpoint_host"
    uci set network.@$peer_section[0].endpoint_port="$endpoint_port"
    uci set network.@$peer_section[0].allowed_ips='0.0.0.0/0'
    uci commit network
}

install_singbox_converter() {
    mkdir -p "$BASE_DIR" "$SINGBOX_SOURCE_DIR"

    local_converter=''
    for candidate in "./singbox-convert.sh" "$(dirname "$0")/singbox-convert.sh"; do
        if [ -f "$candidate" ]; then
            local_converter="$candidate"
            break
        fi
    done

    if [ -n "$local_converter" ]; then
        cp "$local_converter" "$CONVERTER_SCRIPT" || die 'Failed to install singbox-convert.sh'
    else
        warn "singbox-convert.sh was not found next to installer; trying to download from $PROJECT_RAW_BASE"
        if ! fetch_url "$PROJECT_RAW_BASE/singbox-convert.sh" "$CONVERTER_SCRIPT"; then
            die 'Failed to install singbox-convert.sh. Clone the full repository instead of running only getdomains-install.sh.'
        fi
    fi
    chmod +x "$CONVERTER_SCRIPT"
}

create_singbox_placeholder() {
    mkdir -p /etc/sing-box
    if [ ! -f /etc/sing-box/config.json ] || ! grep -q '"interface_name".*"tun0"' /etc/sing-box/config.json; then
        cat > /etc/sing-box/config.json <<'EOF_SB'
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "tun0",
      "address": ["172.16.250.1/30"],
      "auto_route": false,
      "strict_route": false,
      "sniff": true,
      "domain_strategy": "ipv4_only"
    }
  ],
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "proxy",
      "server": "CHANGE_ME",
      "server_port": 443,
      "method": "2022-blake3-aes-128-gcm",
      "password": "CHANGE_ME"
    },
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOF_SB
        warn 'Created /etc/sing-box/config.json template. Edit outbound settings before using sing-box.'
    fi
}

configure_singbox_template() {
    pkg_install sing-box || true
    pkg_install jq || true
    pkg_install coreutils-base64 || true
    mkdir -p /etc/sing-box "$SINGBOX_SOURCE_DIR"
    [ -f /etc/config/sing-box ] && uci -q set sing-box.main.enabled='1' && uci -q set sing-box.main.user='root' && uci -q commit sing-box
    install_singbox_converter

    echo 'Sing-box outbound setup:'
    echo '1) Paste one client link now: vless://, vmess://, trojan:// or ss:// [recommended for 3X-UI]'
    echo '2) Enter a subscription URL from 3X-UI or another panel'
    echo '3) Convert a local file already uploaded to the router: link/subscription/full config.json/outbound.json'
    echo '4) Use existing /etc/sing-box/config.json without changes'
    echo '5) Create placeholder template only'

    while true; do
        IFS= read -r sb_choice || sb_choice='1'
        case "$sb_choice" in
            ''|1)
                link="$(read_secret 'Paste proxy link:')"
                if [ -n "$link" ]; then
                    "$CONVERTER_SCRIPT" --link "$link" || warn 'Sing-box conversion failed. Existing config was kept.'
                else
                    warn 'Empty link; creating placeholder template.'
                    create_singbox_placeholder
                fi
                break
                ;;
            2)
                sub_url="$(read_secret 'Enter subscription URL:')"
                if [ -n "$sub_url" ]; then
                    "$CONVERTER_SCRIPT" --url "$sub_url" || warn 'Subscription conversion failed. Existing config was kept.'
                else
                    warn 'Empty URL; creating placeholder template.'
                    create_singbox_placeholder
                fi
                break
                ;;
            3)
                input_path="$(read_default 'Enter local file path' '/tmp/proxy.txt')"
                if [ -f "$input_path" ]; then
                    "$CONVERTER_SCRIPT" --input "$input_path" || warn 'Local file conversion failed. Existing config was kept.'
                else
                    warn "File not found: $input_path"
                    create_singbox_placeholder
                fi
                break
                ;;
            4)
                if [ -f /etc/sing-box/config.json ]; then
                    if command -v sing-box >/dev/null 2>&1; then
                        sing-box check -c /etc/sing-box/config.json || warn 'Existing sing-box config did not pass sing-box check.'
                    fi
                    log 'Keeping existing /etc/sing-box/config.json'
                else
                    warn 'Existing config not found; creating placeholder template.'
                    create_singbox_placeholder
                fi
                break
                ;;
            5)
                create_singbox_placeholder
                break
                ;;
            *) echo 'Choose 1-5' ;;
        esac
    done

    /etc/init.d/sing-box enable >/dev/null 2>&1 || true
    /etc/init.d/sing-box restart >/dev/null 2>&1 || true
}

select_tunnel() {
    echo 'Select tunnel/interface for marked traffic:'
    echo '1) Configure WireGuard as wg0'
    echo '2) Configure AmneziaWG as awg0'
    echo '3) Use OpenVPN/tun0 (manual OpenVPN config)'
    echo '4) Use Sing-box/tun0 (template will be created)'
    echo '5) Use tun2socks/tun0 (manual config)'
    echo '6) Skip tunnel setup, only install routing/lists'

    while true; do
        IFS= read -r choice || choice='6'
        case "$choice" in
            1)
                TUNNEL='wg'
                TUN_DEV='wg0'
                configure_wg_interface 'wg0' 'wg'
                ensure_firewall_zone 'wg' 'wg0' '' 'REJECT'
                ensure_hotplug_route 'wg0'
                break
                ;;
            2)
                TUNNEL='awg'
                TUN_DEV='awg0'
                configure_wg_interface 'awg0' 'awg'
                ensure_firewall_zone 'awg' 'awg0' '' 'REJECT'
                ensure_hotplug_route 'awg0'
                break
                ;;
            3)
                TUNNEL='ovpn'
                TUN_DEV='tun0'
                pkg_install openvpn-openssl || true
                ensure_firewall_zone 'ovpn' '' 'tun0' 'REJECT'
                ensure_hotplug_route 'tun0'
                break
                ;;
            4)
                TUNNEL='singbox'
                TUN_DEV='tun0'
                configure_singbox_template
                ensure_firewall_zone 'singbox' '' 'tun0' 'ACCEPT'
                ensure_hotplug_route 'tun0'
                break
                ;;
            5)
                TUNNEL='tun2socks'
                TUN_DEV='tun0'
                ensure_firewall_zone 'tun2socks' '' 'tun0' 'REJECT'
                ensure_hotplug_route 'tun0'
                break
                ;;
            6|'')
                TUNNEL='0'
                break
                ;;
            *) echo 'Choose 1-6' ;;
        esac
    done
    uci commit firewall >/dev/null 2>&1 || true
}

write_update_script() {
    cat > "$UPDATE_SCRIPT" <<'EOF_UPDATE'
#!/bin/sh

set -u

BASE_DIR='/etc/domain-routing'
CFG_FILE="$BASE_DIR/config"
LOCK_DIR='/var/lock/domain-routing.lock'

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

fetch_url() {
    url="$1"
    out="$2"
    if cmd_exists curl; then
        curl -4 -fsSL --connect-timeout 10 --max-time 50 --retry 2 -o "$out" "$url"
    else
        wget -4 -q -T 50 -O "$out" "$url"
    fi
}

trim_line() {
    sed 's/#.*$//; s/\r$//; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

valid_domain() {
    printf '%s\n' "$1" | grep -Eq '^([A-Za-z0-9_*-]+\.)+[A-Za-z]{2,}$'
}

normalize_domain() {
    printf '%s\n' "$1" | sed 's#^https\?://##; s#/.*$##; s/^\*\.//; s/^\.//; s/[[:space:]]//g' | tr 'A-Z' 'a-z'
}

valid_ipv4_or_cidr() {
    printf '%s\n' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$'
}

acquire_lock() {
    i=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -gt 20 ] && { warn 'another update is still running'; exit 1; }
        sleep 1
    done
    trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM
}

load_config() {
    [ -f "$CFG_FILE" ] && . "$CFG_FILE"

    DOMAIN_SET="${DOMAIN_SET:-vpn_domains}"
    IP_SET="${IP_SET:-vpn_ip}"
    NFT_FAMILY="${NFT_FAMILY:-inet}"
    NFT_TABLE="${NFT_TABLE:-fw4}"
    DNSMASQ_DIR="${DNSMASQ_DIR:-/etc/dnsmasq.d}"
    DNSMASQ_FILE="${DNSMASQ_FILE:-$DNSMASQ_DIR/90-domain-routing.conf}"
    DOMAINS_DIR="${DOMAINS_DIR:-$BASE_DIR/domains}"
    IPS_DIR="${IPS_DIR:-$BASE_DIR/ips}"
    GEN_DIR="${GEN_DIR:-$BASE_DIR/generated}"
    IP_LOAD_FILE="${IP_LOAD_FILE:-$GEN_DIR/vpn_ip.lst}"
    USE_REMOTE_DOMAINS="${USE_REMOTE_DOMAINS:-0}"
    REMOTE_DOMAINS_URL="${REMOTE_DOMAINS_URL:-}"
    REMOTE_IP_URLS="${REMOTE_IP_URLS:-}"
}

write_local_domain_rules() {
    output="$1"
    for file in "$DOMAINS_DIR"/*.lst; do
        [ -f "$file" ] || continue
        while IFS= read -r raw || [ -n "$raw" ]; do
            line="$(printf '%s\n' "$raw" | trim_line)"
            [ -n "$line" ] || continue
            case "$line" in
                nftset=*|ipset=*)
                    printf '%s\n' "$line" >> "$output"
                    ;;
                *)
                    domain="$(normalize_domain "$line")"
                    if valid_domain "$domain"; then
                        printf 'nftset=/%s/4#%s#%s#%s\n' "$domain" "$NFT_FAMILY" "$NFT_TABLE" "$DOMAIN_SET" >> "$output"
                    else
                        warn "ignored invalid domain: $line"
                    fi
                    ;;
            esac
        done < "$file"
    done
}

update_domains() {
    mkdir -p "$DNSMASQ_DIR" "$GEN_DIR" "$DOMAINS_DIR"
    tmp="$GEN_DIR/domains.conf.tmp"
    remote_tmp="$GEN_DIR/remote-domains.tmp"
    remote_cache="$GEN_DIR/remote-domains.cache"

    {
        printf '# Generated by /etc/domain-routing/getdomains-update.sh\n'
        printf '# Local source directory: %s\n' "$DOMAINS_DIR"
    } > "$tmp"

    if [ "$USE_REMOTE_DOMAINS" = '1' ] && [ -n "$REMOTE_DOMAINS_URL" ]; then
        if fetch_url "$REMOTE_DOMAINS_URL" "$remote_tmp" && [ -s "$remote_tmp" ]; then
            cp "$remote_tmp" "$remote_cache"
            printf '\n# Remote list: %s\n' "$REMOTE_DOMAINS_URL" >> "$tmp"
            cat "$remote_tmp" >> "$tmp"
            printf '\n' >> "$tmp"
        elif [ -s "$remote_cache" ]; then
            warn "remote domain list unavailable; using cached remote list"
            printf '\n# Cached remote list: %s\n' "$REMOTE_DOMAINS_URL" >> "$tmp"
            cat "$remote_cache" >> "$tmp"
            printf '\n' >> "$tmp"
        else
            warn "remote domain list unavailable and no cache exists; using local rules only"
        fi
    fi

    printf '\n# Local manual domain rules\n' >> "$tmp"
    write_local_domain_rules "$tmp"

    if dnsmasq --conf-file="$tmp" --test >/tmp/domain-routing-dnsmasq-test.log 2>&1; then
        if [ ! -f "$DNSMASQ_FILE" ] || ! cmp -s "$tmp" "$DNSMASQ_FILE"; then
            cp "$tmp" "$DNSMASQ_FILE"
            return 10
        fi
        return 0
    fi

    warn 'generated dnsmasq config is invalid; keeping previous valid config'
    cat /tmp/domain-routing-dnsmasq-test.log >&2 2>/dev/null || true
    return 1
}

update_ips() {
    mkdir -p "$GEN_DIR" "$IPS_DIR"
    tmp="$GEN_DIR/vpn_ip.lst.tmp"
    remote_tmp="$GEN_DIR/remote-ip.tmp"

    : > "$tmp"
    for file in "$IPS_DIR"/*.lst; do
        [ -f "$file" ] || continue
        while IFS= read -r raw || [ -n "$raw" ]; do
            line="$(printf '%s\n' "$raw" | trim_line)"
            [ -n "$line" ] || continue
            if valid_ipv4_or_cidr "$line"; then
                printf '%s\n' "$line" >> "$tmp"
            else
                warn "ignored invalid IPv4/CIDR: $line"
            fi
        done < "$file"
    done

    for url in $REMOTE_IP_URLS; do
        cache_id="$(printf '%s\n' "$url" | cksum | awk '{print $1}')"
        remote_cache="$GEN_DIR/remote-ip-$cache_id.cache"
        if fetch_url "$url" "$remote_tmp" && [ -s "$remote_tmp" ]; then
            cp "$remote_tmp" "$remote_cache"
            source_file="$remote_tmp"
        elif [ -s "$remote_cache" ]; then
            warn "remote IP list unavailable, using cached copy: $url"
            source_file="$remote_cache"
        else
            warn "remote IP list unavailable and no cache exists: $url"
            continue
        fi
        while IFS= read -r raw || [ -n "$raw" ]; do
            line="$(printf '%s\n' "$raw" | trim_line)"
            [ -n "$line" ] || continue
            valid_ipv4_or_cidr "$line" && printf '%s\n' "$line" >> "$tmp"
        done < "$source_file"
    done

    sort -u "$tmp" -o "$tmp"
    if [ ! -f "$IP_LOAD_FILE" ] || ! cmp -s "$tmp" "$IP_LOAD_FILE"; then
        cp "$tmp" "$IP_LOAD_FILE"
        return 10
    fi
    return 0
}

restart_services() {
    restart_fw="$1"
    restart_dns="$2"
    if [ "$restart_fw" = '1' ]; then
        /etc/init.d/firewall restart >/dev/null 2>&1 || warn 'firewall restart failed'
    fi
    if [ "$restart_dns" = '1' ]; then
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || warn 'dnsmasq restart failed'
    fi
}

status_report() {
    load_config
    echo "dnsmasq file: $DNSMASQ_FILE"
    [ -s "$DNSMASQ_FILE" ] && wc -l "$DNSMASQ_FILE" || echo 'dnsmasq file is empty or missing'
    echo "ip file: $IP_LOAD_FILE"
    [ -s "$IP_LOAD_FILE" ] && wc -l "$IP_LOAD_FILE" || echo 'ip file is empty or missing'
    if cmd_exists nft; then
        nft list set "$NFT_FAMILY" "$NFT_TABLE" "$DOMAIN_SET" 2>/dev/null | head -20 || true
        nft list set "$NFT_FAMILY" "$NFT_TABLE" "$IP_SET" 2>/dev/null | head -20 || true
    fi
}

main() {
    case "${1:-update}" in
        status)
            status_report
            exit 0
            ;;
    esac

    acquire_lock
    load_config

    dns_changed=0
    fw_changed=0

    update_ips
    rc=$?
    [ "$rc" -eq 10 ] && fw_changed=1

    update_domains
    rc=$?
    [ "$rc" -eq 10 ] && dns_changed=1

    # Firewall restart reloads loadfile sets and recreates nft sets; restart dnsmasq afterwards to repopulate domain nftsets.
    if [ "$fw_changed" = '1' ]; then
        dns_changed=1
    fi
    restart_services "$fw_changed" "$dns_changed"
    log 'domain-routing update complete'
}

main "$@"
EOF_UPDATE
    chmod +x "$UPDATE_SCRIPT"
}

write_init_script() {
    cat > "$INIT_SCRIPT" <<EOF_INIT
#!/bin/sh /etc/rc.common

START=99
STOP=10

EXTRA_COMMANDS='update status'
EXTRA_HELP='        update  Regenerate lists and restart services when needed\n        status  Show generated files and nft sets'

start() {
    $UPDATE_SCRIPT update
}

restart() {
    start
}

reload() {
    start
}

update() {
    start
}

status() {
    $UPDATE_SCRIPT status
}
EOF_INIT
    chmod +x "$INIT_SCRIPT"
    "$INIT_SCRIPT" enable >/dev/null 2>&1 || true
}

ensure_cron() {
    touch /etc/crontabs/root
    if ! grep -Fq '/etc/init.d/getdomains start' /etc/crontabs/root; then
        echo "$CRON_LINE" >> /etc/crontabs/root
    fi
    /etc/init.d/cron enable >/dev/null 2>&1 || true
    /etc/init.d/cron restart >/dev/null 2>&1 || true
}

install_base_packages() {
    pkg_update
    pkg_install curl || true
    pkg_install ca-bundle || true
    pkg_install ip-full || true
    install_dnsmasq_full
}

main() {
    check_system
    warn 'Backup your OpenWrt configuration before continuing. This script changes firewall, network and dnsmasq settings.'
    echo 'Press Enter to continue or Ctrl+C to abort.'
    IFS= read -r _continue || true

    ensure_directories
    seed_lists
    select_domain_source
    write_config
    install_base_packages
    ensure_dnsmasq_confdir
    ensure_rt_table
    ensure_network_mark_rule
    ensure_firewall
    select_tunnel
    write_update_script
    write_init_script
    ensure_cron

    log 'Starting getdomains update'
    "$INIT_SCRIPT" start || true

    log 'Restarting network'
    /etc/init.d/network restart >/dev/null 2>&1 || true

    log 'Done'
    echo "Edit domains in: $DOMAINS_DIR"
    echo "Edit IP/CIDR lists in: $IPS_DIR"
    echo "After edits run: /etc/init.d/getdomains start"
}

main "$@"
