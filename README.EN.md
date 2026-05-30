# Domain routing for OpenWrt / ImmortalWrt / X-Wrt

> Based on: [itdoginfo/domain-routing-openwrt](https://github.com/itdoginfo/domain-routing-openwrt).
>
> This is not the original project. It is a maintenance update for OpenWrt-like firmware with fw4/nftables: OpenWrt, ImmortalWrt, X-Wrt, and compatible builds.

The main reliability change is persistent storage under `/etc/domain-routing`; generated dnsmasq configuration is written to `/etc/dnsmasq.d/90-domain-routing.conf`. Temporary files are no longer the only source of truth, and failed remote downloads do not erase the last valid config.

## Changes from the original project

- Domain/IP state moved from `/tmp` to persistent `/etc/domain-routing`.
- Generated dnsmasq file moved to `/etc/dnsmasq.d/90-domain-routing.conf`.
- Manual list directories added: `/etc/domain-routing/domains/*.lst` and `/etc/domain-routing/ips/*.lst`.
- Remote downloads now use timeouts, locking, and fallback to the last valid cache.
- Updated for OpenWrt-like firmware with fw4/nftables and dnsmasq `nftset`: OpenWrt, ImmortalWrt, X-Wrt, and compatible builds.
- Added automatic `apk`/`opkg` handling: OpenWrt 25.12+ commonly uses `apk`, while many forks and 23/24 branches still use `opkg`.
- Tunnel handling refreshed for WireGuard, AmneziaWG, OpenVPN/tun0, Sing-box/tun0, and tun2socks/tun0.

Install:

```sh
sh getdomains-install.sh
```

Manual domain lists:

```sh
/etc/domain-routing/domains/*.lst
```

Manual IPv4/CIDR lists:

```sh
/etc/domain-routing/ips/*.lst
```

Regenerate and reload:

```sh
/etc/init.d/getdomains start
```

Check:

```sh
sh getdomains-check.sh
/etc/init.d/getdomains status
```

Uninstall while keeping manual lists:

```sh
sh getdomains-uninstall.sh
```

Purge everything:

```sh
sh getdomains-uninstall.sh --purge
```



## OpenWrt-like firmware compatibility

The installer is intended to work on official OpenWrt, ImmortalWrt, X-Wrt, and compatible builds if UCI, fw4/firewall4, nftables, and dnsmasq `nftset` support are available. Legacy fw3/iptables setup is not configured by this profile.

The bootstrap now detects `apk` or `opkg`, does not reject forks just because the firmware name differs, retries downloads with `curl -k`/`wget --no-check-certificate`, retries opkg certificate failures with `--no-check-certificate`, and prints a short diagnosis for package errors such as CA/TLS failures, repository signature issues, network/DNS failures, kmod/kernel mismatches, or low flash space.

Strict TLS mode:

```sh
STRICT_TLS=1 ALLOW_INSECURE_DOWNLOADS=0 sh install.sh
```


## One-command install

This command downloads the bootstrap installer from your repository `dagmagnat/Routing-OpenWrt`, updates router dependencies, downloads the project, and starts the installer:

```sh
cd /tmp && (wget -O install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh || curl -fsSL -o install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh) && sh install.sh
```

If the firmware has HTTPS/CA certificate issues:

```sh
cd /tmp
wget --no-check-certificate -O install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh
ALLOW_INSECURE_DOWNLOADS=1 sh install.sh
```

Curl variant:

```sh
cd /tmp
curl -k -fsSL -o install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh
ALLOW_INSECURE_DOWNLOADS=1 sh install.sh
```

Offline variant: copy the extracted project to the router and run:

```sh
cd /tmp/Routing-OpenWrt
sh getdomains-install.sh
```

This command does not download the old upstream project. The upstream repository is mentioned only as attribution in README and `NOTICE.md`.

## GitHub installation from dagmagnat

After publishing this maintenance fork, installation should use your repository. The original repository remains credited as the upstream base only.

```sh
cd /tmp
if command -v apk >/dev/null 2>&1; then
  apk update
  apk add git curl ca-bundle jq
else
  opkg update
  opkg install git git-http curl ca-bundle jq
fi
rm -rf Routing-OpenWrt
git clone --depth=1 https://github.com/dagmagnat/Routing-OpenWrt.git
cd Routing-OpenWrt
sh getdomains-install.sh
```

## Sing-box link/subscription/JSON converter

When `Sing-box/tun0` is selected, the installer can now import a pasted `vless://`, `vmess://`, `trojan://` or `ss://` link, a subscription URL, a local file, a full sing-box `config.json`, or a single outbound JSON object.

Manual usage:

```sh
/etc/domain-routing/singbox-convert.sh --link 'vless://...'
/etc/domain-routing/singbox-convert.sh --url 'https://panel.example/sub/...'
/etc/domain-routing/singbox-convert.sh --input /tmp/proxy.txt
/etc/domain-routing/singbox-convert.sh --json /tmp/config.json
```

Output: `/etc/sing-box/config.json`.


## Safer interactive installer notes

The installer now supports simple navigation in the main menus: enter `0` to go back where safe, or `q` to stop the installer. WG/AWG pasted config errors and Sing-box conversion errors no longer terminate the whole wizard; the installer returns to the relevant menu so you can retry.

By default, DNS values from WireGuard/AmneziaWG client configs are not imported into the UCI tunnel interface. This is intentional: dnsmasq/nftset domain routing is reliable only when LAN clients resolve names through the router. To opt in manually, edit `/etc/domain-routing/config` and set:

```sh
USE_TUNNEL_DNS="1"
```
