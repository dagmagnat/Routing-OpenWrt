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
