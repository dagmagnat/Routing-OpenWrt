# Domain routing OpenWrt 24/25

> Based on: [itdoginfo/domain-routing-openwrt](https://github.com/itdoginfo/domain-routing-openwrt).
>
> This is not the original project. It is a maintenance update for OpenWrt 24.10/25.12 with persistent list storage, safer updates, fw4/nftables changes, and manual domain/IP list management.

The main reliability change is persistent storage under `/etc/domain-routing`; generated dnsmasq configuration is written to `/etc/dnsmasq.d/90-domain-routing.conf`. Temporary files are no longer the only source of truth, and failed remote downloads do not erase the last valid config.

## Changes from the original project

- Domain/IP state moved from `/tmp` to persistent `/etc/domain-routing`.
- Generated dnsmasq file moved to `/etc/dnsmasq.d/90-domain-routing.conf`.
- Manual list directories added: `/etc/domain-routing/domains/*.lst` and `/etc/domain-routing/ips/*.lst`.
- Remote downloads now use timeouts, locking, and fallback to the last valid cache.
- Updated for OpenWrt 24.10/25.12, fw4/nftables, and dnsmasq `nftset`.
- Added `apk` support for OpenWrt 25.12 while keeping `opkg` support for 24.10/23.05.
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



## One-command install

This command downloads the bootstrap installer from your repository `dagmagnat/Routing-OpenWrt`, updates router dependencies, downloads the project, and starts the installer:

```sh
cd /tmp && (wget -O install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh || curl -fsSL -o install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh) && sh install.sh
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
