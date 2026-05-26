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
