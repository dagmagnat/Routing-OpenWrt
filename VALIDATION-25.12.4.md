# Validation notes for OpenWrt 25.12.4

Checked on 2026-05-26 against the public OpenWrt 25.12.4 package indexes and local shell syntax checks.

## What was checked locally

- `sh -n getdomains-install.sh`
- `sh -n getdomains-uninstall.sh`
- `sh -n getdomains-check.sh`
- Basic template scan for legacy unstable patterns:
  - `/tmp/dnsmasq.d`
  - `/tmp/lst`
  - `ip route add`
  - infinite `while true` network wait loops

Result: no shell syntax errors in the three shell entry scripts; no legacy unstable patterns found in templates.

## OpenWrt 25.12.4 compatibility assumptions

OpenWrt 25.12 uses `apk` instead of `opkg`, so `getdomains-install.sh` detects the available package manager and uses `apk add` on 25.12 systems.

The following package names were visible in the OpenWrt 25.12.4 x86_64 package feeds during the check:

- `dnsmasq-full`
- `ip-full`
- `wireguard-tools`
- `curl`
- `ca-bundle`
- `openvpn-openssl`
- `sing-box`

For other CPU targets, package availability should be confirmed from the matching OpenWrt feed for that device.

## What still must be checked on the router

Run after installation:

```sh
sh getdomains-check.sh
/etc/init.d/getdomains status
nft list set inet fw4 vpn_domains
nft list set inet fw4 vpn_ip
ip rule show
ip route show table vpn
```

If testing Sing-box, confirm that `tun0` exists after starting sing-box:

```sh
ip addr show tun0
/etc/init.d/sing-box restart
logread -e sing-box
```

If testing AmneziaWG, confirm that `awg0` exists after interface startup:

```sh
ifup awg0
ip addr show awg0
logread -e amnezia -e awg
```
