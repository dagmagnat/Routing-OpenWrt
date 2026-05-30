## v8

- Добавлен импорт полного AmneziaWG/WireGuard-конфига `[Interface]` + `[Peer]` прямо во время установки.
- Добавлена поддержка расширенных параметров AmneziaWG: `S3`, `S4`, `I1`, `I2`, `I3`, `I4`, `I5`.
- Рекомендуемый сценарий для AmneziaWG теперь — вставить весь готовый конфиг и завершить ввод строкой `END`, чтобы не переписывать длинный `I1 = <b ...>` вручную.


## v7

- Исправлено ощущение зависания после сообщения `Пакеты AmneziaWG уже установлены`: подсказки для ввода ключей теперь выводятся в stderr, а значение читается отдельно.
- Добавлено явное сообщение перед вводом параметров WireGuard/AmneziaWG.

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

## v6 - AmneziaWG reinstall guard and safer dnsmasq-full upgrade

- Added AmneziaWG readiness checks. If `kmod-amneziawg`, `amneziawg-tools` and the `amneziawg` netifd/LuCI protocol handler are already present, the installer skips the external AmneziaWG installer.
- Wrapped the external AmneziaWG installer with a timeout and closed stdin so it cannot hang indefinitely after package installation.
- Stopped replacing `/etc/config/dhcp` with `/etc/config/dhcp-opkg` after installing `dnsmasq-full`. Existing DHCP/DNS settings are preserved.
- Bootstrap installer now creates `/tmp/Routing-OpenWrt` as a convenient symlink to the extracted GitHub archive directory, so interrupted installs are easier to resume.

## v9

- Добавлен режим надёжности для доменной маршрутизации: перехват DNS TCP/UDP 53 с LAN на dnsmasq.
- Добавлен опциональный IPv4-only режим: отключение RA/DHCPv6/NDP на LAN, чтобы IPv6 не обходил IPv4-маршрутизацию.
- Установщик стал легче для роутеров 16 MB flash: `jq` и `curl` больше не ставятся в bootstrap без необходимости.
- `getdomains-check.sh` теперь проверяет DNS redirect и предупреждает, если IPv6 LAN не отключён.
- Uninstall удаляет DNS redirect, созданный domain-routing.

## v8 - Safer interactive installer and DNS protection

- Added navigation in the interactive installer: `0` returns to the previous menu where safe, `q` stops the installer cleanly.
- AmneziaWG/WireGuard import no longer exits the whole installer on malformed pasted config. Missing `END`, empty config, missing `PrivateKey`, `Address` or `PublicKey` now keeps the user inside the tunnel setup menu.
- Manual WG/AWG setup validates required fields before applying UCI changes, so a half-entered peer is less likely to be committed.
- DNS from WireGuard/AmneziaWG client configs is ignored by default via `USE_TUNNEL_DNS=0`, because provider DNS on the tunnel interface can break dnsmasq/nftset based domain routing.
- Sing-box converter is installed only when a link/subscription/local conversion is actually selected. Existing `/etc/sing-box/config.json` and placeholder modes no longer fail just because the converter cannot be downloaded.
- Invalid IPv4/CIDR entries are now checked more strictly: octets must be 0..255 and CIDR mask must be 0..32.

## v10 - Portable installer for OpenWrt forks

- Relaxed firmware detection: the installer now accepts OpenWrt-like systems such as ImmortalWrt and X-Wrt if UCI/fw4/nftables are present.
- Added permissive HTTPS fallback for firmware with missing/stale CA certificates: `curl -k`, `wget --no-check-certificate`, and `opkg ... --no-check-certificate` retry paths.
- Added package error diagnosis for TLS/CA errors, repository signature/key problems, network/DNS failures, kmod/kernel mismatches, and low flash/overlay space.
- `dnsmasq-full` installation is no longer a blind hard stop: the installer checks whether the current dnsmasq already supports `nftset`, tries package-manager alternatives, and warns clearly if domain routing cannot work yet.
- README now documents normal, certificate-fallback, strict-TLS, and offline installation commands.
