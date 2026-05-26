# Notice / Attribution

This maintenance version is based on the original project:

- [itdoginfo/domain-routing-openwrt](https://github.com/itdoginfo/domain-routing-openwrt)

The upstream project did not include a separate license file in the archive used for this maintenance update. Keep this attribution when publishing or sharing modified versions.

Main maintenance changes in this package:

- Persistent storage under `/etc/domain-routing` instead of relying on `/tmp`.
- dnsmasq config generation under `/etc/dnsmasq.d/90-domain-routing.conf`.
- Manual domain/IP list directories.
- Safer remote list update flow with timeout, cache, lock, and validation.
- OpenWrt 24.10/25.12 compatibility updates.
