#!/bin/sh

# Convert common 3X-UI/Xray client links or subscription output to a sing-box
# TUN client config for Routing-OpenWrt.
# Supported input: vless://, vmess://, trojan://, ss://, plain/base64 subscriptions,
# full sing-box config.json, or a single sing-box outbound JSON object.

set -u

BASE_DIR="${BASE_DIR:-/etc/domain-routing}"
SINGBOX_DIR="${SINGBOX_DIR:-/etc/sing-box}"
SOURCE_DIR="${SOURCE_DIR:-$BASE_DIR/singbox}"
OUTPUT_CONFIG="${OUTPUT_CONFIG:-$SINGBOX_DIR/config.json}"
TUN_NAME="${TUN_NAME:-tun0}"
TUN_ADDRESS="${TUN_ADDRESS:-172.16.250.1/30}"
PROXY_TAG="${PROXY_TAG:-proxy}"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

need_jq() {
    cmd_exists jq || die 'jq is required for conversion. Install it first: opkg update && opkg install jq, or apk update && apk add jq'
}

fetch_url() {
    url="$1"
    out="$2"
    if cmd_exists curl; then
        curl -4 -fsSL --connect-timeout 10 --max-time 60 --retry 2 -o "$out" "$url"
    elif cmd_exists wget; then
        wget -4 -q -T 60 -O "$out" "$url"
    else
        die 'curl or wget is required to download subscription URLs'
    fi
}

url_decode() {
    # Small safe decoder for the characters commonly used in Xray client links.
    # BusyBox ash/sed friendly; intentionally not a full URL decoder.
    printf '%s' "$1" | sed \
        -e 's/%2[Ff]/\//g' \
        -e 's/%3[Aa]/:/g' \
        -e 's/%40/@/g' \
        -e 's/%3[Dd]/=/g' \
        -e 's/%26/\&/g' \
        -e 's/%2[Bb]/+/g' \
        -e 's/%20/ /g' \
        -e 's/%23/#/g' \
        -e 's/%5[Bb]/[/g' \
        -e 's/%5[Dd]/]/g'
}

b64_normalize() {
    data="$(printf '%s' "$1" | tr '_-' '/+' | tr -d '\r\n\t ')"
    rem=$(( ${#data} % 4 ))
    if [ "$rem" -eq 2 ]; then
        data="${data}=="
    elif [ "$rem" -eq 3 ]; then
        data="${data}="
    elif [ "$rem" -eq 1 ]; then
        return 1
    fi
    printf '%s' "$data"
}

b64_decode_str() {
    normalized="$(b64_normalize "$1")" || return 1
    if cmd_exists base64; then
        printf '%s' "$normalized" | base64 -d 2>/dev/null
    elif cmd_exists openssl; then
        printf '%s' "$normalized" | openssl enc -base64 -d -A 2>/dev/null
    else
        die 'base64 decoder is required'
    fi
}

QUERY=''
MAIN=''
SCHEME=''
USERINFO=''
SERVER=''
PORT=''

parse_uri_parts() {
    uri="$1"
    SCHEME="${uri%%://*}"
    rest="${uri#*://}"
    rest="${rest%%#*}"
    if [ "$rest" != "${rest%%\?*}" ]; then
        QUERY="${rest#*\?}"
        MAIN="${rest%%\?*}"
    else
        QUERY=''
        MAIN="$rest"
    fi

    case "$MAIN" in
        *@*)
            USERINFO="${MAIN%@*}"
            hostport="${MAIN#*@}"
            ;;
        *)
            USERINFO=''
            hostport="$MAIN"
            ;;
    esac

    case "$hostport" in
        \[*\]:*)
            SERVER="$(printf '%s' "$hostport" | sed -n 's/^\[\(.*\)\]:\([0-9][0-9]*\)$/\1/p')"
            PORT="$(printf '%s' "$hostport" | sed -n 's/^\[\(.*\)\]:\([0-9][0-9]*\)$/\2/p')"
            ;;
        *)
            SERVER="${hostport%:*}"
            PORT="${hostport##*:}"
            ;;
    esac
}

qparam() {
    key="$1"
    value="$(printf '%s' "$QUERY" | tr '&' '\n' | sed -n "s/^$key=//p" | head -n 1)"
    [ -n "$value" ] && url_decode "$value" || true
}

valid_port() {
    printf '%s\n' "$1" | grep -Eq '^[0-9]{1,5}$'
}

transport_jq() {
    cat <<'JQ'
def transport($tr; $path; $host; $service_name):
  if $tr == "ws" then
    {transport: ({type:"ws"}
      + (if $path != "" then {path:$path} else {} end)
      + (if $host != "" then {headers:{Host:$host}} else {} end))}
  elif $tr == "grpc" then
    {transport: ({type:"grpc"}
      + (if $service_name != "" then {service_name:$service_name} else {} end))}
  elif $tr == "http" then
    {transport: ({type:"http"}
      + (if $host != "" then {host:[$host]} else {} end)
      + (if $path != "" then {path:$path} else {} end))}
  elif $tr == "httpupgrade" then
    {transport: ({type:"httpupgrade"}
      + (if $path != "" then {path:$path} else {} end)
      + (if $host != "" then {host:$host} else {} end))}
  elif $tr == "xhttp" then
    {transport: ({type:"xhttp"}
      + (if $path != "" then {path:$path} else {} end)
      + (if $host != "" then {host:$host} else {} end))}
  else {} end;
JQ
}

make_vless_outbound() {
    link="$1"
    need_jq
    parse_uri_parts "$link"
    uuid="$(url_decode "$USERINFO")"
    [ -n "$uuid" ] || die 'VLESS UUID is empty'
    [ -n "$SERVER" ] || die 'VLESS server is empty'
    valid_port "$PORT" || die "VLESS port is invalid: $PORT"

    tr_type="$(qparam type)"; [ -n "$tr_type" ] || tr_type='tcp'
    security="$(qparam security)"; [ -n "$security" ] || security='none'
    flow="$(qparam flow)"
    sni="$(qparam sni)"; [ -n "$sni" ] || sni="$(qparam serverName)"
    fp="$(qparam fp)"; [ -n "$fp" ] || fp="$(qparam fingerprint)"
    pbk="$(qparam pbk)"; [ -n "$pbk" ] || pbk="$(qparam publicKey)"
    sid="$(qparam sid)"; [ -n "$sid" ] || sid="$(qparam shortId)"
    path="$(qparam path)"
    host="$(qparam host)"
    service_name="$(qparam serviceName)"; [ -n "$service_name" ] || service_name="$(qparam service_name)"

    jq -n \
      --arg tag "$PROXY_TAG" --arg server "$SERVER" --arg port "$PORT" --arg uuid "$uuid" \
      --arg flow "$flow" --arg security "$security" --arg sni "$sni" --arg fp "$fp" \
      --arg pbk "$pbk" --arg sid "$sid" --arg tr "$tr_type" --arg path "$path" \
      --arg host "$host" --arg service_name "$service_name" "$(transport_jq)"'
{
  type: "vless", tag: $tag, server: $server, server_port: ($port|tonumber), uuid: $uuid
}
+ (if $flow != "" then {flow: $flow} else {} end)
+ (if ($security == "tls" or $security == "reality") then
    {tls: ({enabled: true}
      + (if $sni != "" then {server_name: $sni} else {} end)
      + (if $fp != "" then {utls: {enabled: true, fingerprint: $fp}} else {} end)
      + (if $security == "reality" then {reality: ({enabled: true}
          + (if $pbk != "" then {public_key: $pbk} else {} end)
          + (if $sid != "" then {short_id: $sid} else {} end))} else {} end))}
   else {} end)
+ transport($tr; $path; $host; $service_name)
'
}

make_trojan_outbound() {
    link="$1"
    need_jq
    parse_uri_parts "$link"
    password="$(url_decode "$USERINFO")"
    [ -n "$password" ] || die 'Trojan password is empty'
    [ -n "$SERVER" ] || die 'Trojan server is empty'
    valid_port "$PORT" || die "Trojan port is invalid: $PORT"

    tr_type="$(qparam type)"; [ -n "$tr_type" ] || tr_type='tcp'
    security="$(qparam security)"; [ -n "$security" ] || security='tls'
    sni="$(qparam sni)"; [ -n "$sni" ] || sni="$(qparam peer)"; [ -n "$sni" ] || sni="$(qparam serverName)"
    fp="$(qparam fp)"; [ -n "$fp" ] || fp="$(qparam fingerprint)"
    path="$(qparam path)"
    host="$(qparam host)"
    service_name="$(qparam serviceName)"; [ -n "$service_name" ] || service_name="$(qparam service_name)"

    jq -n \
      --arg tag "$PROXY_TAG" --arg server "$SERVER" --arg port "$PORT" --arg password "$password" \
      --arg security "$security" --arg sni "$sni" --arg fp "$fp" --arg tr "$tr_type" \
      --arg path "$path" --arg host "$host" --arg service_name "$service_name" "$(transport_jq)"'
{
  type: "trojan", tag: $tag, server: $server, server_port: ($port|tonumber), password: $password
}
+ (if ($security == "tls" or $security == "reality") then
    {tls: ({enabled: true}
      + (if $sni != "" then {server_name: $sni} else {} end)
      + (if $fp != "" then {utls: {enabled: true, fingerprint: $fp}} else {} end))}
   else {} end)
+ transport($tr; $path; $host; $service_name)
'
}

make_shadowsocks_outbound() {
    link="$1"
    need_jq
    parse_uri_parts "$link"

    userinfo="$USERINFO"
    hostport_main="$MAIN"
    if [ -z "$userinfo" ]; then
        # Old form: ss://base64(method:password@host:port)
        decoded="$(b64_decode_str "$hostport_main" 2>/dev/null || true)"
        [ -n "$decoded" ] || die 'Cannot decode Shadowsocks link'
        userinfo="${decoded%@*}"
        hp="${decoded#*@}"
        SERVER="${hp%:*}"
        PORT="${hp##*:}"
    else
        decoded_userinfo="$(b64_decode_str "$userinfo" 2>/dev/null || true)"
        if [ -n "$decoded_userinfo" ]; then
            userinfo="$decoded_userinfo"
        else
            userinfo="$(url_decode "$userinfo")"
        fi
    fi

    method="${userinfo%%:*}"
    password="${userinfo#*:}"
    [ -n "$method" ] || die 'Shadowsocks method is empty'
    [ -n "$password" ] || die 'Shadowsocks password is empty'
    [ -n "$SERVER" ] || die 'Shadowsocks server is empty'
    valid_port "$PORT" || die "Shadowsocks port is invalid: $PORT"

    jq -n --arg tag "$PROXY_TAG" --arg server "$SERVER" --arg port "$PORT" \
      --arg method "$method" --arg password "$password" \
      '{type:"shadowsocks", tag:$tag, server:$server, server_port:($port|tonumber), method:$method, password:$password}'
}

make_vmess_outbound() {
    link="$1"
    need_jq
    payload="${link#vmess://}"
    decoded="$(b64_decode_str "$payload")" || die 'Cannot decode VMess link'
    printf '%s' "$decoded" | jq -e . >/dev/null || die 'VMess payload is not valid JSON'

    server="$(printf '%s' "$decoded" | jq -r '.add // .server // empty')"
    port="$(printf '%s' "$decoded" | jq -r '(.port // .server_port // empty)|tostring')"
    uuid="$(printf '%s' "$decoded" | jq -r '.id // .uuid // empty')"
    security="$(printf '%s' "$decoded" | jq -r '.scy // .security // "auto"')"
    alter_id="$(printf '%s' "$decoded" | jq -r '(.aid // .alterId // .alter_id // 0)|tonumber')"
    tls_mode="$(printf '%s' "$decoded" | jq -r '.tls // empty')"
    sni="$(printf '%s' "$decoded" | jq -r '.sni // .serverName // empty')"
    fp="$(printf '%s' "$decoded" | jq -r '.fp // .fingerprint // empty')"
    tr_type="$(printf '%s' "$decoded" | jq -r '.net // .type // "tcp"')"
    path="$(printf '%s' "$decoded" | jq -r '.path // empty')"
    host="$(printf '%s' "$decoded" | jq -r '.host // empty')"
    service_name="$(printf '%s' "$decoded" | jq -r '.serviceName // .service_name // empty')"

    [ -n "$server" ] || die 'VMess server is empty'
    valid_port "$port" || die "VMess port is invalid: $port"
    [ -n "$uuid" ] || die 'VMess UUID is empty'

    jq -n \
      --arg tag "$PROXY_TAG" --arg server "$server" --arg port "$port" --arg uuid "$uuid" \
      --arg security "$security" --argjson alter_id "$alter_id" --arg tls_mode "$tls_mode" \
      --arg sni "$sni" --arg fp "$fp" --arg tr "$tr_type" --arg path "$path" \
      --arg host "$host" --arg service_name "$service_name" "$(transport_jq)"'
{
  type: "vmess", tag: $tag, server: $server, server_port: ($port|tonumber), uuid: $uuid,
  security: $security, alter_id: $alter_id
}
+ (if ($tls_mode != "" and $tls_mode != "none") then
    {tls: ({enabled: true}
      + (if $sni != "" then {server_name: $sni} else {} end)
      + (if $fp != "" then {utls: {enabled: true, fingerprint: $fp}} else {} end))}
   else {} end)
+ transport($tr; $path; $host; $service_name)
'
}

wrap_outbound_config() {
    outbound_file="$1"
    out_tmp="$2"
    need_jq
    jq -n \
      --slurpfile outbound "$outbound_file" \
      --arg tun "$TUN_NAME" \
      --arg addr "$TUN_ADDRESS" \
      --arg proxy "$PROXY_TAG" \
      '{
        log: {level: "info"},
        inbounds: [
          {
            type: "tun",
            interface_name: $tun,
            address: [$addr],
            auto_route: false,
            strict_route: false,
            sniff: true,
            domain_strategy: "ipv4_only"
          }
        ],
        outbounds: [
          $outbound[0],
          {type: "direct", tag: "direct"},
          {type: "block", tag: "block"}
        ],
        route: {
          auto_detect_interface: true,
          final: $proxy
        }
      }' > "$out_tmp"
}

validate_singbox_config() {
    file="$1"
    if cmd_exists sing-box; then
        sing-box check -c "$file" >/tmp/domain-routing-singbox-check.log 2>&1 || {
            cat /tmp/domain-routing-singbox-check.log >&2 2>/dev/null || true
            return 1
        }
    elif cmd_exists jq; then
        jq -e . "$file" >/dev/null || return 1
    fi
    return 0
}

install_config() {
    src="$1"
    mkdir -p "$SINGBOX_DIR" "$SOURCE_DIR"
    tmp="$OUTPUT_CONFIG.tmp.$$"
    cp "$src" "$tmp"
    if validate_singbox_config "$tmp"; then
        if [ -f "$OUTPUT_CONFIG" ]; then
            cp "$OUTPUT_CONFIG" "$OUTPUT_CONFIG.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
        fi
        mv "$tmp" "$OUTPUT_CONFIG"
        log "Installed sing-box config: $OUTPUT_CONFIG"
        return 0
    fi
    rm -f "$tmp"
    die 'Generated sing-box config is invalid; previous config was kept'
}

convert_link_to_config() {
    link="$1"
    mkdir -p "$SOURCE_DIR"
    outbound_tmp="$SOURCE_DIR/outbound.tmp.$$"
    config_tmp="$SOURCE_DIR/config.tmp.$$"

    case "$link" in
        vless://*) make_vless_outbound "$link" > "$outbound_tmp" || die "failed to convert VLESS link" ;;
        vmess://*) make_vmess_outbound "$link" > "$outbound_tmp" || die "failed to convert VMess link" ;;
        trojan://*) make_trojan_outbound "$link" > "$outbound_tmp" || die "failed to convert Trojan link" ;;
        ss://*) make_shadowsocks_outbound "$link" > "$outbound_tmp" || die "failed to convert Shadowsocks link" ;;
        *) die 'Unsupported link scheme. Supported: vless://, vmess://, trojan://, ss://' ;;
    esac

    jq -e '.tag = "'"$PROXY_TAG"'"' "$outbound_tmp" > "$outbound_tmp.normalized" && mv "$outbound_tmp.normalized" "$outbound_tmp" || die "generated outbound JSON is invalid"
    cp "$outbound_tmp" "$SOURCE_DIR/outbound.json"
    wrap_outbound_config "$outbound_tmp" "$config_tmp"
    install_config "$config_tmp"
    rm -f "$outbound_tmp" "$config_tmp"
}

first_link_from_file() {
    file="$1"
    grep -Eo '(vless|vmess|trojan|ss)://[^[:space:]"<>]+' "$file" | head -n 1 && return 0

    compact="$(tr -d '\r\n\t ' < "$file")"
    decoded="$(b64_decode_str "$compact" 2>/dev/null || true)"
    if [ -n "$decoded" ]; then
        printf '%s\n' "$decoded" | grep -Eo '(vless|vmess|trojan|ss)://[^[:space:]"<>]+' | head -n 1 && return 0
    fi
    return 1
}

convert_json_file() {
    file="$1"
    need_jq
    jq -e . "$file" >/dev/null || die 'JSON file is invalid'
    mkdir -p "$SOURCE_DIR"

    if jq -e 'has("inbounds") and has("outbounds")' "$file" >/dev/null; then
        cp "$file" "$SOURCE_DIR/config.imported.json"
        install_config "$file"
        return 0
    fi

    if jq -e 'has("type") and (.type|type == "string")' "$file" >/dev/null; then
        outbound_tmp="$SOURCE_DIR/outbound.imported.json"
        config_tmp="$SOURCE_DIR/config.tmp.$$"
        jq '.tag = "'"$PROXY_TAG"'"' "$file" > "$outbound_tmp"
        wrap_outbound_config "$outbound_tmp" "$config_tmp"
        install_config "$config_tmp"
        rm -f "$config_tmp"
        return 0
    fi

    die 'JSON is valid, but it is neither a full sing-box config nor a single outbound object'
}

convert_input_file() {
    file="$1"
    [ -s "$file" ] || die "input file is empty or missing: $file"
    first_char="$(sed -n 's/^[[:space:]]*\(.\).*$/\1/p' "$file" | head -n 1)"
    if [ "$first_char" = '{' ]; then
        convert_json_file "$file"
        return 0
    fi

    link="$(first_link_from_file "$file" || true)"
    [ -n "$link" ] || die 'No supported proxy link found in file/subscription'
    printf '%s\n' "$link" > "$SOURCE_DIR/proxy.url"
    convert_link_to_config "$link"
}

usage() {
    cat <<USAGE
Usage:
  $0 --link 'vless://...'
  $0 --url 'https://panel.example/sub/...'
  $0 --input /path/to/link-or-subscription.txt
  $0 --json /path/to/sing-box-config-or-outbound.json
  $0 --help

Output:
  $OUTPUT_CONFIG

Notes:
  - Subscription input may be plain newline-separated links or base64 encoded.
  - Full sing-box JSON configs are copied after validation.
  - Single outbound JSON objects are wrapped into a TUN config on $TUN_NAME.
USAGE
}

main() {
    mkdir -p "$SOURCE_DIR"
    case "${1:-}" in
        --link)
            [ $# -ge 2 ] || die '--link requires an argument'
            printf '%s\n' "$2" > "$SOURCE_DIR/proxy.url"
            convert_link_to_config "$2"
            ;;
        --url|--subscription)
            [ $# -ge 2 ] || die '--url requires an argument'
            printf '%s\n' "$2" > "$SOURCE_DIR/subscription.url"
            tmp="$SOURCE_DIR/subscription.downloaded.$$"
            fetch_url "$2" "$tmp"
            convert_input_file "$tmp"
            rm -f "$tmp"
            ;;
        --input)
            [ $# -ge 2 ] || die '--input requires a file path'
            convert_input_file "$2"
            ;;
        --json)
            [ $# -ge 2 ] || die '--json requires a file path'
            convert_json_file "$2"
            ;;
        --help|-h|'')
            usage
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
}

main "$@"
