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
PROJECT_RAW_BASE="${PROJECT_RAW_BASE:-https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main}"
INIT_SCRIPT='/etc/init.d/getdomains'
TABLE_NAME='vpn'
TABLE_ID='99'
MARK='0x1'
DOMAIN_SET='vpn_domains'
IP_SET='vpn_ip'
NFT_FAMILY='inet'
NFT_TABLE='fw4'
CRON_LINE='17 */8 * * * /etc/init.d/getdomains start >/tmp/getdomains.log 2>&1'
BACK_RC=97
STOP_RC=98

log() { printf "$GREEN%s$NC\n" "$*"; }
warn() { printf "$YELLOW%s$NC\n" "$*"; }
err() { printf "$RED%s$NC\n" "$*"; }
die() { err "$*"; exit 1; }

is_back_choice() {
    case "${1:-}" in
        0|b|B|back|Back|назад|Назад) return 0 ;;
        *) return 1 ;;
    esac
}

is_stop_choice() {
    case "${1:-}" in
        q|Q|quit|Quit|exit|Exit|стоп|Стоп|выход|Выход) return 0 ;;
        *) return 1 ;;
    esac
}

show_nav_hint() {
    echo 'Навигация: 0 — назад, q — остановить установку без продолжения.'
}

input_error() {
    warn "$*"
    warn 'Исправьте ввод и повторите пункт. Можно ввести 0 для возврата назад.'
}

read_default() {
    prompt="$1"
    default="$2"
    # Prompt goes to stderr because the returned value is captured with command substitution.
    # If this is printed to stdout, OpenWrt appears to "hang" while actually waiting for hidden input.
    printf "%s [%s]: " "$prompt" "$default" >&2
    IFS= read -r answer || answer=''
    if [ -z "$answer" ]; then
        printf '%s' "$default"
    else
        printf '%s' "$answer"
    fi
}

read_secret() {
    prompt="$1"
    # Prompt goes to stderr because stdout is used as the function return value.
    printf "%s " "$prompt" >&2
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
        die 'Не найден ни apk, ни opkg'
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
        log "$package уже установлен"
        return 0
    fi

    pm="$(pkg_manager)"
    log "Устанавливаю пакет: $package"
    if [ "$pm" = 'apk' ]; then
        apk add "$package"
    elif [ "$pm" = 'opkg' ]; then
        opkg install "$package"
    else
        die 'Не найден ни apk, ни opkg'
    fi
}

install_dnsmasq_full() {
    if pkg_installed dnsmasq-full; then
        log 'dnsmasq-full уже установлен'
        return 0
    fi

    pm="$(pkg_manager)"
    if [ "$pm" = 'apk' ]; then
        log 'Устанавливаю dnsmasq-full через apk'
        apk add dnsmasq-full || die 'Не удалось установить dnsmasq-full'
    else
        log 'Устанавливаю dnsmasq-full через opkg'
        opkg update || die 'opkg update завершился с ошибкой'
        cd /tmp || die 'Не удалось перейти в /tmp'
        rm -f /tmp/dnsmasq-full*.ipk
        opkg download dnsmasq-full || die 'Не удалось скачать dnsmasq-full'
        opkg remove dnsmasq >/dev/null 2>&1 || true
        opkg install /tmp/dnsmasq-full*.ipk || opkg install dnsmasq-full || die 'Не удалось установить dnsmasq-full'
        if [ -f /etc/config/dhcp-opkg ]; then
            warn 'opkg создал /etc/config/dhcp-opkg. Текущий /etc/config/dhcp не перезаписываю.'
            warn 'Это нормально: OpenWrt сохранил ваши текущие настройки DHCP/DNS.'
        fi
    fi
}

check_system() {
    [ -r /etc/os-release ] || die '/etc/os-release не найден. Этот скрипт предназначен для OpenWrt.'
    . /etc/os-release
    version_id="${VERSION_ID:-0}"
    major="${version_id%%.*}"
    [ -n "$major" ] || major=0

    model='unknown'
    [ -r /tmp/sysinfo/model ] && model="$(cat /tmp/sysinfo/model)"
    printf "$BLUE%s$NC\n" "Модель: $model"
    printf "$BLUE%s$NC\n" "OpenWrt: ${OPENWRT_RELEASE:-$version_id}"

    case "$major" in
        23|24|25) : ;;
        *) die 'Поддерживаются OpenWrt 23.05, 24.10 и 25.12. Основная цель проекта — 24/25.' ;;
    esac

    if [ "$major" -lt 22 ]; then
        die 'Режим fw4/nftables требует OpenWrt 22.03 или новее.'
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
    echo 'Выберите источник удалённого списка доменов:'
    echo '1) Только локальные списки вручную [рекомендуется, пока нет своего списка]'
    echo '2) Список Russia inside из itdoginfo/allow-domains'
    echo '3) Список Russia outside из itdoginfo/allow-domains'
    echo '4) Список Ukraine из itdoginfo/allow-domains'
    echo '5) Свой raw URL со списком dnsmasq/nftset'
    echo '6) Отключить удалённый список'
    show_nav_hint
    echo
    echo 'Нажмите Enter для варианта 1.'
    while true; do
        printf 'Ваш выбор [1]: '
        IFS= read -r choice || choice='1'
        is_stop_choice "$choice" && return "$STOP_RC"
        case "$choice" in
            0)
                warn 'Это первый шаг мастера, возвращаться некуда. Для остановки введите q.'
                ;;
            ''|1)
                USE_REMOTE_DOMAINS='0'
                REMOTE_DOMAINS_URL=''
                return 0
                ;;
            2)
                USE_REMOTE_DOMAINS='1'
                REMOTE_DOMAINS_URL='https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/inside-dnsmasq-nfset.lst'
                return 0
                ;;
            3)
                USE_REMOTE_DOMAINS='1'
                REMOTE_DOMAINS_URL='https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/outside-dnsmasq-nfset.lst'
                return 0
                ;;
            4)
                USE_REMOTE_DOMAINS='1'
                REMOTE_DOMAINS_URL='https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Ukraine/inside-dnsmasq-nfset.lst'
                return 0
                ;;
            5)
                REMOTE_DOMAINS_URL="$(read_secret 'Вставьте raw URL со списком dnsmasq/nftset или 0 для возврата:')"
                if is_back_choice "$REMOTE_DOMAINS_URL"; then
                    continue
                fi
                is_stop_choice "$REMOTE_DOMAINS_URL" && return "$STOP_RC"
                case "$REMOTE_DOMAINS_URL" in
                    http://*|https://*)
                        USE_REMOTE_DOMAINS='1'
                        return 0
                        ;;
                    *)
                        input_error 'URL должен начинаться с http:// или https://.'
                        ;;
                esac
                ;;
            6)
                USE_REMOTE_DOMAINS='0'
                REMOTE_DOMAINS_URL=''
                return 0
                ;;
            *) echo 'Введите число от 1 до 6, 0 или q.' ;;
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

# Reliability options for domain-based routing.
# DNS interception is important because dnsmasq.nftset only works when clients resolve names through this router.
FORCE_LAN_DNS="${FORCE_LAN_DNS:-1}"
# By default the installer does not import DNS from WG/AWG client configs, because changing router/interface DNS often breaks domain routing.
# Set USE_TUNNEL_DNS=1 manually only if you intentionally want the tunnel provider DNS on the interface.
USE_TUNNEL_DNS="${USE_TUNNEL_DNS:-0}"
# Most AWG/WG/OpenVPN client configs in this project are IPv4-only. IPv6 can bypass domain routing.
DISABLE_LAN_IPV6="${DISABLE_LAN_IPV6:-1}"
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

ensure_lan_dns_default() {
    # DHCP option 6: выдаём клиентам IP роутера как DNS, но не удаляем пользовательские DHCP options.
    # На стандартном OpenWrt это обычно уже так, но явная опция полезна на кастомных сборках.
    lan_ip="$(uci -q get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1')"
    if ! uci -q show dhcp.lan 2>/dev/null | grep -Fq "dhcp_option='6,$lan_ip'"; then
        uci add_list dhcp.lan.dhcp_option="6,$lan_ip"
        uci commit dhcp
    fi
}

ensure_force_lan_dns() {
    # Перехватываем обычный DNS/53 с LAN на локальный dnsmasq.
    # DoH/DoT это не ломает и не перехватывает, но обычные hardcoded DNS 8.8.8.8/1.1.1.1 закрывает.
    [ "${FORCE_LAN_DNS:-1}" = '1' ] || return 0
    lan_ip="$(uci -q get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1')"

    for proto in udp tcp; do
        name="domainrouting_force_dns_$proto"
        sec="$(find_uci_section firewall redirect "$name")"
        if [ -z "$sec" ]; then
            uci add firewall redirect >/dev/null
            sec='@redirect[-1]'
            uci set firewall.$sec.name="$name"
        fi
        uci set firewall.$sec.src='lan'
        uci set firewall.$sec.proto="$proto"
        uci set firewall.$sec.src_dport='53'
        uci set firewall.$sec.dest_ip="$lan_ip"
        uci set firewall.$sec.dest_port='53'
        uci set firewall.$sec.target='DNAT'
        uci set firewall.$sec.family='ipv4'
        uci set firewall.$sec.reflection='0'
    done
    uci commit firewall
}

ensure_ipv6_mode() {
    [ "${DISABLE_LAN_IPV6:-1}" = '1' ] || return 0
    warn 'Включён IPv4-only режим для LAN: отключаю RA/DHCPv6/NDP, чтобы IPv6 не обходил доменную маршрутизацию.'
    uci set dhcp.lan.ra='disabled'
    uci set dhcp.lan.dhcpv6='disabled'
    uci set dhcp.lan.ndp='disabled'
    uci set network.lan.delegate='0'
    uci commit dhcp
    uci commit network
}

select_safety_options() {
    echo 'Дополнительные параметры надёжности:'
    echo '1) Включить перехват DNS на роутер и отключить IPv6 на LAN [рекомендуется для AWG/WG/OpenVPN IPv4]'
    echo '2) Только перехват DNS на роутер, IPv6 не трогать'
    echo '3) Ничего не менять'
    show_nav_hint
    echo
    echo 'Нажмите Enter для варианта 1.'
    while true; do
        printf 'Ваш выбор [1]: '
        IFS= read -r safety_choice || safety_choice='1'
        is_back_choice "$safety_choice" && return "$BACK_RC"
        is_stop_choice "$safety_choice" && return "$STOP_RC"
        case "$safety_choice" in
            ''|1)
                FORCE_LAN_DNS='1'
                DISABLE_LAN_IPV6='1'
                return 0
                ;;
            2)
                FORCE_LAN_DNS='1'
                DISABLE_LAN_IPV6='0'
                return 0
                ;;
            3)
                FORCE_LAN_DNS='0'
                DISABLE_LAN_IPV6='0'
                return 0
                ;;
            *) echo 'Введите число от 1 до 3, 0 или q.' ;;
        esac
    done
}
install_wireguard() {
    pkg_install wireguard-tools
}

awg_core_installed() {
    pkg_installed kmod-amneziawg && pkg_installed amneziawg-tools
}

awg_proto_installed() {
    pkg_installed luci-proto-amneziawg || [ -f /lib/netifd/proto/amneziawg.sh ]
}

awg_ready() {
    awg_core_installed && awg_proto_installed
}

run_with_timeout() {
    timeout_seconds="$1"
    shift
    "$@" &
    pid="$!"
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$timeout_seconds" ]; then
            warn "Команда выполняется дольше ${timeout_seconds} секунд, останавливаю её и продолжаю проверку установленных пакетов."
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wait "$pid"
}

install_awg_packages() {
    if awg_ready; then
        log 'Пакеты AmneziaWG уже установлены, пропускаю установку.'
        return 0
    fi

    if awg_core_installed; then
        warn 'kmod-amneziawg и amneziawg-tools уже установлены, но протокол amneziawg для netifd/LuCI не найден.'
        warn 'Попробую дозагрузить недостающий компонент через установщик AmneziaWG.'
    fi

    url='https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh'
    tmp='/tmp/amneziawg-install.sh'
    log 'Устанавливаю пакеты AmneziaWG через установщик Slava-Shchipunov/awg-openwrt'
    if fetch_url "$url" "$tmp"; then
        chmod +x "$tmp"
        # -en: non-interactive package installation mode from upstream installer.
        # stdin закрыт, чтобы внешний установщик не мог зависнуть на вопросе пользователю.
        run_with_timeout 300 sh "$tmp" -en </dev/null || warn 'Установщик AmneziaWG завершился с ошибкой или был остановлен по таймауту. Проверяю, что уже установлено.'
    else
        warn 'Не удалось скачать установщик AmneziaWG. Установите AWG-пакеты вручную и запустите скрипт ещё раз.'
    fi

    if awg_ready; then
        log 'AmneziaWG уже готов к настройке, продолжаю установку маршрутизации.'
        return 0
    fi

    if awg_core_installed; then
        warn 'Основные пакеты AmneziaWG установлены, но протокол amneziawg для UCI/netifd не найден.'
        warn 'Если интерфейс awg0 не поднимется, установите luci-proto-amneziawg и запустите скрипт повторно.'
        return 0
    fi

    warn 'AmneziaWG не установлен. Установите kmod-amneziawg и amneziawg-tools, затем повторите этот пункт.'
    return 1
}

set_network_opt() {
    section="$1"
    option="$2"
    value="$3"

    # DNS from provider client configs is intentionally ignored by default.
    # Domain routing through dnsmasq/nftset is reliable only when LAN clients resolve via the router.
    if [ "$option" = 'dns' ] && [ "${USE_TUNNEL_DNS:-0}" != '1' ]; then
        uci -q delete network.$section.$option >/dev/null 2>&1 || true
        return 0
    fi

    if [ -n "$value" ]; then
        uci set network.$section.$option="$value"
    else
        uci -q delete network.$section.$option >/dev/null 2>&1 || true
    fi
}

trim_string() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

normalize_list_value() {
    printf '%s' "$1" | sed 's/,/ /g;s/[[:space:]][[:space:]]*/ /g;s/^[[:space:]]*//;s/[[:space:]]*$//'
}

read_multiline_config() {
    out_file="$1"
    : > "$out_file" || { warn "Не удалось создать временный файл $out_file"; return 1; }
    echo 'Вставьте полный конфиг AmneziaWG/WireGuard начиная с [Interface].'
    echo 'После вставки напишите отдельной строкой END и нажмите Enter.'
    echo 'До вставки можно ввести 0, чтобы вернуться назад.'
    echo 'Пример окончания:'
    echo 'END'
    got_end='0'
    got_content='0'
    while IFS= read -r line; do
        if [ "$line" = 'END' ]; then
            got_end='1'
            break
        fi
        if [ "$got_content" = '0' ] && is_back_choice "$line"; then
            return "$BACK_RC"
        fi
        if [ "$got_content" = '0' ] && is_stop_choice "$line"; then
            return "$STOP_RC"
        fi
        [ -n "$line" ] && got_content='1'
        printf '%s\n' "$line" >> "$out_file"
    done

    if [ "$got_end" != '1' ]; then
        input_error 'Не найден завершающий маркер END. Конфиг не применён.'
        return 1
    fi
    if [ ! -s "$out_file" ]; then
        input_error 'Конфиг пустой. Настройка не применена.'
        return 1
    fi
    return 0
}
parse_endpoint_value() {
    endpoint="$1"
    endpoint_host=''
    endpoint_port=''
    case "$endpoint" in
        \[*\]:*)
            endpoint_host="$(printf '%s' "$endpoint" | sed 's/^\[\(.*\)\]:\([0-9][0-9]*\)$/\1/')"
            endpoint_port="$(printf '%s' "$endpoint" | sed 's/^\[\(.*\)\]:\([0-9][0-9]*\)$/\2/')"
            ;;
        *:*)
            endpoint_host="${endpoint%:*}"
            endpoint_port="${endpoint##*:}"
            ;;
        *)
            endpoint_host="$endpoint"
            endpoint_port=''
            ;;
    esac
}

reset_peer_sections() {
    peer_section="$1"
    while uci -q delete network.@$peer_section[0] >/dev/null 2>&1; do
        :
    done
}

apply_wg_config_file() {
    config_file="$1"
    iface="$2"
    peer_type="$3"
    proto="$4"
    peer_section="$5"

    section=''
    private_key=''
    address=''
    dns=''
    listen_port='51820'
    awg_jc=''
    awg_jmin=''
    awg_jmax=''
    awg_s1=''
    awg_s2=''
    awg_s3=''
    awg_s4=''
    awg_h1=''
    awg_h2=''
    awg_h3=''
    awg_h4=''
    awg_i1=''
    awg_i2=''
    awg_i3=''
    awg_i4=''
    awg_i5=''
    public_key=''
    preshared_key=''
    endpoint=''
    allowed_ips='0.0.0.0/0'
    persistent_keepalive='25'

    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        line="$(printf '%s' "$raw_line" | tr -d '\r')"
        trimmed="$(trim_string "$line")"
        [ -z "$trimmed" ] && continue
        case "$trimmed" in
            \#*|\;*) continue ;;
            \[*\])
                section="$(printf '%s' "$trimmed" | sed 's/^\[//;s/\]$//' | tr '[:upper:]' '[:lower:]')"
                continue
                ;;
        esac
        case "$trimmed" in
            *=*) ;;
            *) continue ;;
        esac
        key="$(trim_string "${trimmed%%=*}" | tr '[:upper:]' '[:lower:]')"
        value="$(trim_string "${trimmed#*=}")"
        [ -z "$value" ] && continue

        case "$section:$key" in
            interface:privatekey) private_key="$value" ;;
            interface:address) address="$(normalize_list_value "$value")" ;;
            interface:dns) dns="$(normalize_list_value "$value")" ;;
            interface:listenport) listen_port="$value" ;;
            interface:jc) awg_jc="$value" ;;
            interface:jmin) awg_jmin="$value" ;;
            interface:jmax) awg_jmax="$value" ;;
            interface:s1) awg_s1="$value" ;;
            interface:s2) awg_s2="$value" ;;
            interface:s3) awg_s3="$value" ;;
            interface:s4) awg_s4="$value" ;;
            interface:h1) awg_h1="$value" ;;
            interface:h2) awg_h2="$value" ;;
            interface:h3) awg_h3="$value" ;;
            interface:h4) awg_h4="$value" ;;
            interface:i1) awg_i1="$value" ;;
            interface:i2) awg_i2="$value" ;;
            interface:i3) awg_i3="$value" ;;
            interface:i4) awg_i4="$value" ;;
            interface:i5) awg_i5="$value" ;;
            peer:publickey) public_key="$value" ;;
            peer:presharedkey) preshared_key="$value" ;;
            peer:endpoint) endpoint="$value" ;;
            peer:allowedips) allowed_ips="$(normalize_list_value "$value")" ;;
            peer:persistentkeepalive) persistent_keepalive="$value" ;;
        esac
    done < "$config_file"

    if [ -z "$private_key" ]; then input_error 'В конфиге не найден PrivateKey в секции [Interface].'; return 1; fi
    if [ -z "$address" ]; then input_error 'В конфиге не найден Address в секции [Interface].'; return 1; fi
    if [ -z "$public_key" ]; then input_error 'В конфиге не найден PublicKey в секции [Peer].'; return 1; fi
    if [ -z "$endpoint" ]; then warn 'В конфиге не найден Endpoint. Интерфейс будет создан, но туннель может не подняться без endpoint_host/endpoint_port.'; fi

    uci set network.$iface=interface || return 1
    uci set network.$iface.proto="$proto" || return 1
    uci set network.$iface.private_key="$private_key" || return 1
    uci set network.$iface.addresses="$address" || return 1
    set_network_opt "$iface" listen_port "$listen_port" || return 1
    set_network_opt "$iface" dns "$dns" || return 1

    if [ "$peer_type" = 'awg' ]; then
        set_network_opt "$iface" awg_jc "$awg_jc" || return 1
        set_network_opt "$iface" awg_jmin "$awg_jmin" || return 1
        set_network_opt "$iface" awg_jmax "$awg_jmax" || return 1
        set_network_opt "$iface" awg_s1 "$awg_s1" || return 1
        set_network_opt "$iface" awg_s2 "$awg_s2" || return 1
        set_network_opt "$iface" awg_s3 "$awg_s3" || return 1
        set_network_opt "$iface" awg_s4 "$awg_s4" || return 1
        set_network_opt "$iface" awg_h1 "$awg_h1" || return 1
        set_network_opt "$iface" awg_h2 "$awg_h2" || return 1
        set_network_opt "$iface" awg_h3 "$awg_h3" || return 1
        set_network_opt "$iface" awg_h4 "$awg_h4" || return 1
        set_network_opt "$iface" awg_i1 "$awg_i1" || return 1
        set_network_opt "$iface" awg_i2 "$awg_i2" || return 1
        set_network_opt "$iface" awg_i3 "$awg_i3" || return 1
        set_network_opt "$iface" awg_i4 "$awg_i4" || return 1
        set_network_opt "$iface" awg_i5 "$awg_i5" || return 1
    fi

    reset_peer_sections "$peer_section"
    uci add network "$peer_section" >/dev/null || return 1
    uci set network.@$peer_section[0].name="${iface}_client" || return 1
    uci set network.@$peer_section[0].public_key="$public_key" || return 1
    set_network_opt "@$peer_section[0]" preshared_key "$preshared_key" || return 1
    uci set network.@$peer_section[0].route_allowed_ips='0' || return 1
    uci set network.@$peer_section[0].allowed_ips="$allowed_ips" || return 1
    set_network_opt "@$peer_section[0]" persistent_keepalive "$persistent_keepalive" || return 1
    if [ -n "$endpoint" ]; then
        parse_endpoint_value "$endpoint"
        set_network_opt "@$peer_section[0]" endpoint_host "$endpoint_host" || return 1
        set_network_opt "@$peer_section[0]" endpoint_port "$endpoint_port" || return 1
    else
        uci -q delete network.@$peer_section[0].endpoint_host >/dev/null 2>&1 || true
        uci -q delete network.@$peer_section[0].endpoint_port >/dev/null 2>&1 || true
    fi

    uci commit network || return 1
    log "Конфиг $iface применён через UCI."
}

configure_wg_manual() {
    iface="$1"
    peer_type="$2"
    proto="$3"
    peer_section="$4"

    echo 'Теперь введите параметры клиента из конфигурации туннеля.'
    echo 'DNS из клиентского конфига по умолчанию НЕ импортируется, чтобы не ломать dnsmasq/nftset маршрутизацию.'
    show_nav_hint

    private_key="$(read_secret 'Введите PrivateKey из секции [Interface] или 0 для возврата:')"
    is_back_choice "$private_key" && return "$BACK_RC"
    is_stop_choice "$private_key" && return "$STOP_RC"
    address="$(read_default 'Введите Address с маской, например 10.8.0.2/32 или 192.168.100.5/24' '10.8.0.2/32')"
    is_back_choice "$address" && return "$BACK_RC"
    is_stop_choice "$address" && return "$STOP_RC"
    dns="$(read_secret 'Введите DNS из секции [Interface] или оставьте пустым:')"
    is_back_choice "$dns" && return "$BACK_RC"
    is_stop_choice "$dns" && return "$STOP_RC"

    awg_jc=''
    awg_jmin=''
    awg_jmax=''
    awg_s1=''
    awg_s2=''
    awg_s3=''
    awg_s4=''
    awg_h1=''
    awg_h2=''
    awg_h3=''
    awg_h4=''
    awg_i1=''
    awg_i2=''
    awg_i3=''
    awg_i4=''
    awg_i5=''

    if [ "$peer_type" = 'awg' ]; then
        echo 'Введите параметры AmneziaWG. Если параметра нет в конфиге, оставьте пустым.'
        awg_jc="$(read_default 'Введите Jc' '3')"
        awg_jmin="$(read_default 'Введите Jmin' '10')"
        awg_jmax="$(read_default 'Введите Jmax' '50')"
        awg_s1="$(read_secret 'Введите S1 или оставьте пустым:')"
        awg_s2="$(read_secret 'Введите S2 или оставьте пустым:')"
        awg_s3="$(read_secret 'Введите S3 или оставьте пустым:')"
        awg_s4="$(read_secret 'Введите S4 или оставьте пустым:')"
        awg_h1="$(read_secret 'Введите H1 или оставьте пустым:')"
        awg_h2="$(read_secret 'Введите H2 или оставьте пустым:')"
        awg_h3="$(read_secret 'Введите H3 или оставьте пустым:')"
        awg_h4="$(read_secret 'Введите H4 или оставьте пустым:')"
        awg_i1="$(read_secret 'Введите I1 полностью, включая <b ...>, или оставьте пустым:')"
        awg_i2="$(read_secret 'Введите I2 полностью, включая <b ...>, или оставьте пустым:')"
        awg_i3="$(read_secret 'Введите I3 полностью, включая <b ...>, или оставьте пустым:')"
        awg_i4="$(read_secret 'Введите I4 полностью, включая <b ...>, или оставьте пустым:')"
        awg_i5="$(read_secret 'Введите I5 полностью, включая <b ...>, или оставьте пустым:')"
    fi

    public_key="$(read_secret 'Введите PublicKey из секции [Peer]:')"
    preshared_key="$(read_secret 'Введите PresharedKey из секции [Peer] или оставьте пустым:')"
    endpoint_host="$(read_secret 'Введите Endpoint host без порта:')"
    endpoint_port="$(read_default 'Введите Endpoint port' '51820')"
    allowed_ips="$(read_default 'Введите AllowedIPs' '0.0.0.0/0')"
    persistent_keepalive="$(read_default 'Введите PersistentKeepalive' '25')"

    if [ -z "$private_key" ]; then input_error 'PrivateKey пустой. Конфиг не применён.'; return 1; fi
    if [ -z "$address" ]; then input_error 'Address пустой. Конфиг не применён.'; return 1; fi
    if [ -z "$public_key" ]; then input_error 'PublicKey пустой. Конфиг не применён.'; return 1; fi
    if [ -z "$endpoint_host" ]; then input_error 'Endpoint host пустой. Конфиг не применён.'; return 1; fi

    uci set network.$iface=interface || return 1
    uci set network.$iface.proto="$proto" || return 1
    uci set network.$iface.private_key="$private_key" || return 1
    uci set network.$iface.addresses="$(normalize_list_value "$address")" || return 1
    uci set network.$iface.listen_port='51820' || return 1
    set_network_opt "$iface" dns "$(normalize_list_value "$dns")" || return 1

    if [ "$peer_type" = 'awg' ]; then
        set_network_opt "$iface" awg_jc "$awg_jc" || return 1
        set_network_opt "$iface" awg_jmin "$awg_jmin" || return 1
        set_network_opt "$iface" awg_jmax "$awg_jmax" || return 1
        set_network_opt "$iface" awg_s1 "$awg_s1" || return 1
        set_network_opt "$iface" awg_s2 "$awg_s2" || return 1
        set_network_opt "$iface" awg_s3 "$awg_s3" || return 1
        set_network_opt "$iface" awg_s4 "$awg_s4" || return 1
        set_network_opt "$iface" awg_h1 "$awg_h1" || return 1
        set_network_opt "$iface" awg_h2 "$awg_h2" || return 1
        set_network_opt "$iface" awg_h3 "$awg_h3" || return 1
        set_network_opt "$iface" awg_h4 "$awg_h4" || return 1
        set_network_opt "$iface" awg_i1 "$awg_i1" || return 1
        set_network_opt "$iface" awg_i2 "$awg_i2" || return 1
        set_network_opt "$iface" awg_i3 "$awg_i3" || return 1
        set_network_opt "$iface" awg_i4 "$awg_i4" || return 1
        set_network_opt "$iface" awg_i5 "$awg_i5" || return 1
    fi

    reset_peer_sections "$peer_section"
    uci add network "$peer_section" >/dev/null || return 1
    uci set network.@$peer_section[0].name="${iface}_client" || return 1
    uci set network.@$peer_section[0].public_key="$public_key" || return 1
    set_network_opt "@$peer_section[0]" preshared_key "$preshared_key" || return 1
    uci set network.@$peer_section[0].route_allowed_ips='0' || return 1
    uci set network.@$peer_section[0].allowed_ips="$(normalize_list_value "$allowed_ips")" || return 1
    set_network_opt "@$peer_section[0]" persistent_keepalive "$persistent_keepalive" || return 1
    set_network_opt "@$peer_section[0]" endpoint_host "$endpoint_host" || return 1
    set_network_opt "@$peer_section[0]" endpoint_port "$endpoint_port" || return 1
    uci commit network || return 1
    log "Конфиг $iface применён через UCI."
}
configure_wg_interface() {
    iface="$1"
    peer_type="$2"

    if [ "$peer_type" = 'awg' ]; then
        install_awg_packages || return 1
        proto='amneziawg'
        peer_section="amneziawg_$iface"
        while true; do
            echo 'Выберите способ настройки AmneziaWG:'
            echo '1) Вставить весь готовый конфиг [Interface]/[Peer] [рекомендуется]'
            echo '2) Ввести поля вручную'
            show_nav_hint
            echo
            echo 'Нажмите Enter для варианта 1.'
            awg_import_choice="$(read_default 'Ваш выбор' '1')"
            is_back_choice "$awg_import_choice" && return "$BACK_RC"
            is_stop_choice "$awg_import_choice" && return "$STOP_RC"
            case "$awg_import_choice" in
                ''|1)
                    tmp_conf="/tmp/domain-routing-awg-conf.$$"
                    read_multiline_config "$tmp_conf"
                    rc=$?
                    if [ "$rc" -eq "$BACK_RC" ]; then
                        rm -f "$tmp_conf"
                        continue
                    fi
                    if [ "$rc" -eq "$STOP_RC" ]; then
                        rm -f "$tmp_conf"
                        return "$STOP_RC"
                    fi
                    if [ "$rc" -ne 0 ]; then
                        rm -f "$tmp_conf"
                        continue
                    fi
                    if apply_wg_config_file "$tmp_conf" "$iface" "$peer_type" "$proto" "$peer_section"; then
                        rm -f "$tmp_conf"
                        return 0
                    fi
                    rm -f "$tmp_conf"
                    ;;
                2)
                    configure_wg_manual "$iface" "$peer_type" "$proto" "$peer_section"
                    rc=$?
                    [ "$rc" -eq "$BACK_RC" ] && continue
                    return "$rc"
                    ;;
                *) echo 'Введите 1, 2, 0 или q.' ;;
            esac
        done
    else
        install_wireguard || return 1
        proto='wireguard'
        peer_section="wireguard_$iface"
        configure_wg_manual "$iface" "$peer_type" "$proto" "$peer_section"
    fi
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
        cp "$local_converter" "$CONVERTER_SCRIPT" || die 'Не удалось установить singbox-convert.sh'
    else
        warn "singbox-convert.sh не найден рядом с установщиком; пробую скачать из $PROJECT_RAW_BASE"
        if ! fetch_url "$PROJECT_RAW_BASE/singbox-convert.sh" "$CONVERTER_SCRIPT"; then
            die 'Не удалось установить singbox-convert.sh. Скачайте полный репозиторий, а не только getdomains-install.sh.'
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
        warn 'Создан шаблон /etc/sing-box/config.json. Перед использованием sing-box настройте outbound.'
    fi
}

configure_singbox_template() {
    mkdir -p /etc/sing-box "$SINGBOX_SOURCE_DIR"
    [ -f /etc/config/sing-box ] && uci -q set sing-box.main.enabled='1' && uci -q set sing-box.main.user='root' && uci -q commit sing-box

    echo 'Настройка исходящего подключения Sing-box:'
    echo '1) Вставить одну клиентскую ссылку сейчас: vless://, vmess://, trojan:// или ss:// [рекомендуется для 3X-UI]'
    echo '2) Вставить URL подписки из 3X-UI или другой панели'
    echo '3) Конвертировать локальный файл на роутере: ссылка/подписка/full config.json/outbound.json'
    echo '4) Использовать существующий /etc/sing-box/config.json без изменений'
    echo '5) Создать только шаблон /etc/sing-box/config.json'
    show_nav_hint
    echo
    echo 'Нажмите Enter для варианта 1.'

    while true; do
        printf 'Ваш выбор [1]: '
        IFS= read -r sb_choice || sb_choice='1'
        is_back_choice "$sb_choice" && return "$BACK_RC"
        is_stop_choice "$sb_choice" && return "$STOP_RC"
        case "$sb_choice" in
            ''|1)
                pkg_install sing-box || true
                pkg_install jq || true
                pkg_install coreutils-base64 || true
                install_singbox_converter || return 1
                link="$(read_secret 'Вставьте proxy-ссылку или 0 для возврата:')"
                if is_back_choice "$link"; then
                    continue
                fi
                is_stop_choice "$link" && return "$STOP_RC"
                if [ -n "$link" ]; then
                    if "$CONVERTER_SCRIPT" --link "$link"; then
                        break
                    fi
                    input_error 'Конвертация Sing-box не удалась. Старый конфиг сохранён.'
                    continue
                else
                    warn 'Ссылка пустая; создаю шаблон.'
                    create_singbox_placeholder
                fi
                break
                ;;
            2)
                pkg_install sing-box || true
                pkg_install jq || true
                pkg_install coreutils-base64 || true
                install_singbox_converter || return 1
                sub_url="$(read_secret 'Вставьте URL подписки или 0 для возврата:')"
                if is_back_choice "$sub_url"; then
                    continue
                fi
                is_stop_choice "$sub_url" && return "$STOP_RC"
                if [ -n "$sub_url" ]; then
                    if "$CONVERTER_SCRIPT" --url "$sub_url"; then
                        break
                    fi
                    input_error 'Конвертация подписки не удалась. Старый конфиг сохранён.'
                    continue
                else
                    warn 'URL пустой; создаю шаблон.'
                    create_singbox_placeholder
                fi
                break
                ;;
            3)
                pkg_install sing-box || true
                pkg_install jq || true
                pkg_install coreutils-base64 || true
                install_singbox_converter || return 1
                input_path="$(read_default 'Введите путь к локальному файлу' '/tmp/proxy.txt')"
                if is_back_choice "$input_path"; then
                    continue
                fi
                is_stop_choice "$input_path" && return "$STOP_RC"
                if [ -f "$input_path" ]; then
                    if "$CONVERTER_SCRIPT" --input "$input_path"; then
                        break
                    fi
                    input_error 'Конвертация локального файла не удалась. Старый конфиг сохранён.'
                    continue
                else
                    input_error "Файл не найден: $input_path"
                fi
                ;;
            4)
                pkg_install sing-box || true
                if [ -f /etc/sing-box/config.json ]; then
                    if command -v sing-box >/dev/null 2>&1; then
                        sing-box check -c /etc/sing-box/config.json || warn 'Существующий конфиг Sing-box не прошёл проверку sing-box check.'
                    fi
                    log 'Оставляю существующий /etc/sing-box/config.json'
                else
                    warn 'Существующий конфиг не найден; создаю шаблон.'
                    create_singbox_placeholder
                fi
                break
                ;;
            5)
                pkg_install sing-box || true
                create_singbox_placeholder
                break
                ;;
            *) echo 'Введите число от 1 до 5, 0 или q.' ;;
        esac
    done

    /etc/init.d/sing-box enable >/dev/null 2>&1 || true
    /etc/init.d/sing-box restart >/dev/null 2>&1 || true
    return 0
}

select_tunnel() {
    echo 'Выберите туннель/интерфейс для промаркированного трафика:'
    echo '1) Настроить обычный WireGuard как wg0'
    echo '2) Настроить AmneziaWG как awg0'
    echo '3) Использовать OpenVPN/tun0 (конфиг OpenVPN настраивается вручную)'
    echo '4) Использовать Sing-box/tun0 (можно вставить ссылку/подписку/JSON)'
    echo '5) Использовать tun2socks/tun0 (настраивается вручную)'
    echo '6) Пропустить настройку туннеля, установить только маршрутизацию и списки'
    show_nav_hint
    echo
    echo 'Нажмите Enter для варианта 6.'

    while true; do
        printf 'Ваш выбор [6]: '
        IFS= read -r choice || choice='6'
        is_back_choice "$choice" && return "$BACK_RC"
        is_stop_choice "$choice" && return "$STOP_RC"
        case "$choice" in
            1)
                TUNNEL='wg'
                TUN_DEV='wg0'
                configure_wg_interface 'wg0' 'wg'
                rc=$?
                [ "$rc" -eq "$BACK_RC" ] && continue
                [ "$rc" -eq "$STOP_RC" ] && return "$STOP_RC"
                if [ "$rc" -ne 0 ]; then
                    input_error 'WireGuard не настроен. Выберите пункт заново или вернитесь назад.'
                    continue
                fi
                ensure_firewall_zone 'wg' 'wg0' '' 'REJECT'
                ensure_hotplug_route 'wg0'
                break
                ;;
            2)
                TUNNEL='awg'
                TUN_DEV='awg0'
                configure_wg_interface 'awg0' 'awg'
                rc=$?
                [ "$rc" -eq "$BACK_RC" ] && continue
                [ "$rc" -eq "$STOP_RC" ] && return "$STOP_RC"
                if [ "$rc" -ne 0 ]; then
                    input_error 'AmneziaWG не настроен. Выберите пункт заново или вернитесь назад.'
                    continue
                fi
                ensure_firewall_zone 'awg' 'awg0' '' 'REJECT'
                ensure_hotplug_route 'awg0'
                break
                ;;
            3)
                TUNNEL='ovpn'
                TUN_DEV='tun0'
                pkg_install openvpn-openssl || warn 'openvpn-openssl не установлен автоматически. Настройте OpenVPN вручную.'
                ensure_firewall_zone 'ovpn' '' 'tun0' 'REJECT'
                ensure_hotplug_route 'tun0'
                break
                ;;
            4)
                TUNNEL='singbox'
                TUN_DEV='tun0'
                configure_singbox_template
                rc=$?
                [ "$rc" -eq "$BACK_RC" ] && continue
                [ "$rc" -eq "$STOP_RC" ] && return "$STOP_RC"
                if [ "$rc" -ne 0 ]; then
                    input_error 'Sing-box не настроен. Выберите пункт заново или вернитесь назад.'
                    continue
                fi
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
            *) echo 'Введите число от 1 до 6, 0 или q.' ;;
        esac
    done
    uci commit firewall >/dev/null 2>&1 || true
    return 0
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
    value="$1"
    case "$value" in
        */*) ip_part="${value%/*}"; mask_part="${value#*/}" ;;
        *) ip_part="$value"; mask_part='' ;;
    esac
    printf '%s\n' "$ip_part" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
    old_ifs="$IFS"
    IFS='.'
    set -- $ip_part
    IFS="$old_ifs"
    [ $# -eq 4 ] || return 1
    for octet in "$@"; do
        case "$octet" in ''|*[!0-9]*) return 1 ;; esac
        [ "$octet" -le 255 ] 2>/dev/null || return 1
    done
    if [ -n "$mask_part" ]; then
        case "$mask_part" in ''|*[!0-9]*) return 1 ;; esac
        [ "$mask_part" -ge 0 ] 2>/dev/null && [ "$mask_part" -le 32 ] 2>/dev/null || return 1
    fi
    return 0
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
    # Не ставим curl принудительно: на маленьких роутерах 16 МБ flash важен каждый мегабайт.
    # fetch_url умеет работать через встроенный wget; curl ставим только если пользователь выберет сценарий, где он реально нужен.
    pkg_install ca-bundle || true
    pkg_install ip-full || true
    install_dnsmasq_full
}

select_initial_options() {
    while true; do
        select_domain_source
        rc=$?
        [ "$rc" -eq "$STOP_RC" ] && return "$STOP_RC"

        select_safety_options
        rc=$?
        if [ "$rc" -eq "$BACK_RC" ]; then
            continue
        fi
        [ "$rc" -eq "$STOP_RC" ] && return "$STOP_RC"
        return 0
    done
}

main() {
    check_system
    warn 'Перед продолжением сделайте резервную копию настроек OpenWrt. Скрипт изменяет firewall, network и dnsmasq.'
    echo 'Нажмите Enter для продолжения или Ctrl+C для отмены.'
    IFS= read -r _continue || true

    ensure_directories
    seed_lists
    select_initial_options
    rc=$?
    if [ "$rc" -eq "$STOP_RC" ]; then
        warn 'Установка остановлена пользователем до применения основных изменений.'
        exit 0
    fi
    write_config
    install_base_packages
    ensure_dnsmasq_confdir
    ensure_lan_dns_default
    ensure_ipv6_mode
    ensure_rt_table
    ensure_network_mark_rule
    ensure_firewall
    ensure_force_lan_dns
    select_tunnel
    rc=$?
    if [ "$rc" -eq "$STOP_RC" ]; then
        warn 'Установка остановлена пользователем. Уже применённые базовые настройки сохранены; при необходимости запустите getdomains-uninstall.sh.'
        exit 0
    fi
    if [ "$rc" -eq "$BACK_RC" ]; then
        warn 'Возврат из выбора туннеля после применения базовых настроек невозможен без повторного запуска. Запустите скрипт ещё раз, чтобы изменить ранние параметры.'
        exit 0
    fi
    write_update_script
    write_init_script
    ensure_cron

    log 'Запускаю обновление getdomains'
    "$INIT_SCRIPT" start || true

    log 'Перезапускаю network'
    /etc/init.d/network restart >/dev/null 2>&1 || true

    log 'Готово'
    echo "Домены можно менять здесь: $DOMAINS_DIR"
    echo "IP/CIDR списки можно менять здесь: $IPS_DIR"
    echo "После изменений запустите: /etc/init.d/getdomains restart"
    echo 'Если маршрутизация не сработала на телефоне/ПК, отключите Private DNS/DoH и переподключите Wi-Fi.'
}

main "$@"
