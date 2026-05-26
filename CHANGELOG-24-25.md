# Changelog 24/25 maintenance fork

## 2026-05-26

### Attribution

- Added explicit upstream attribution: [itdoginfo/domain-routing-openwrt](https://github.com/itdoginfo/domain-routing-openwrt).
- Added `NOTICE.md` so the original source remains visible when the archive is redistributed.

### Reliability

- Moved domain/IP state from `/tmp` to persistent `/etc/domain-routing`.
- Generated dnsmasq config is now `/etc/dnsmasq.d/90-domain-routing.conf`.
- Update process is atomic: invalid or unavailable remote lists do not overwrite the last valid config.
- Removed infinite network wait loops. Remote downloads have timeouts and retry limits.
- Added update lock to prevent overlapping cron/manual runs.
- Cron moved to an 8-hour refresh with log in `/tmp/getdomains.log`.
- `ip route add` replaced with `ip route replace` in hotplug route scripts.

### OpenWrt 24/25 compatibility

- Uses fw4/nftables and dnsmasq `nftset` mode for OpenWrt 24.10/25.12.
- Adds package-manager abstraction: `apk` on 25.12, `opkg` on 24.10/23.05.
- `dnsmasq-full` installation handles both `apk` and `opkg`.
- dnsmasq `confdir` changed from `/tmp/dnsmasq.d` to `/etc/dnsmasq.d`.

### Manual list management

- Local domains: `/etc/domain-routing/domains/*.lst`.
- Local IPv4/CIDR: `/etc/domain-routing/ips/*.lst`.
- Generated IPv4/CIDR loadfile: `/etc/domain-routing/generated/vpn_ip.lst`.
- Supports custom remote domain list URL and remote IP list URLs in `/etc/domain-routing/config`.

### Tunnel support

- WireGuard: `wg0` automatic UCI setup.
- AmneziaWG: `awg0` automatic UCI setup, package installation delegated to the current upstream `Slava-Shchipunov/awg-openwrt` installer.
- OpenVPN, Sing-box and tun2socks: routing/firewall zone support for `tun0`; Sing-box template is created when selected.

### Diagnostics

- Replaced legacy `getdomains-check.sh` with a focused OpenWrt 24/25 health check.
- `/etc/init.d/getdomains status` shows generated files and nft sets.

## v3 - Sing-box import/converter and dagmagnat install flow

- Added `singbox-convert.sh`.
- Sing-box installer mode now asks how to configure outbound:
  - paste one `vless://`, `vmess://`, `trojan://` or `ss://` link;
  - enter a 3X-UI/subscription URL;
  - convert a local file already uploaded to the router;
  - keep existing `/etc/sing-box/config.json`;
  - create placeholder template only.
- Converter supports plain subscriptions, base64 encoded subscriptions, full sing-box JSON configs, and single outbound JSON objects.
- Installer now uses `dagmagnat/Routing-OpenWrt` as the default raw source when it has to fetch helper files.
- Added explicit installation commands that update router package indexes and install bootstrap dependencies before running the project installer.


## v4 - Correct GitHub repository name and bootstrap installer

- Changed all installation URLs to the actual repository `dagmagnat/Routing-OpenWrt`.
- Added `install.sh`: a bootstrap installer that updates router dependencies first, then downloads and runs the project from `dagmagnat/Routing-OpenWrt`.
- Updated README install commands so users install from your GitHub, while the original project remains only as attribution.
- Updated Ansible metadata to point issue tracking to `dagmagnat/Routing-OpenWrt`.

## v5 - Russian installer menus

- Translated the interactive installer menus and prompts into Russian.
- Added explicit input prompts such as `Ваш выбор [1]:` and `Ваш выбор [6]:` so users see where to type the menu number.
- Translated bootstrap installer messages in `install.sh`.
- Translated the most common Sing-box converter messages.
