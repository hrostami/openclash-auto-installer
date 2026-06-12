# OpenClash Auto Installer

![Release](https://img.shields.io/github/v/release/hrostami/openclash-auto-installer?style=flat-square)
![License](https://img.shields.io/github/license/hrostami/openclash-auto-installer?style=flat-square)
![Workflow](https://img.shields.io/github/actions/workflow/status/hrostami/openclash-auto-installer/shell-check.yml?branch=main&style=flat-square)

Applicable to **OpenWrt / iStoreOS / ImmortalWrt** A collection of agent plug-in installation, update, uninstall and check scripts.

Already integrated:

- OpenClash
- PassWall
- PassWall2
- Nikki
- SmartDNS
- MosDNS

---

## One click to use

It is recommended to use the menu mode directly. Installation, updating, checking version and uninstalling are all in the menu:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/hrostami/openclash-auto-installer/main/menu.sh)"
```

Fixed stable version available Release tags, for example:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/hrostami/openclash-auto-installer/v1.2.4/menu.sh)"
```

if GitHub raw Access is slow, available jsDelivr:

```sh
sh -c "$(curl -fsSL https://cdn.jsdelivr.net/gh/hrostami/openclash-auto-installer@main/menu.sh)"
```

Menu structure:

```text
1. Check for plugin updates
2. Install plugin
3. Uninstall plugin
0. Exit
```

---

## Support scope

Recommended use:

- OpenWrt 24.10.x
- iStoreOS 24.10.x
- ImmortalWrt 24.10.x

You can try but it is recommended to verify first:

- OpenWrt 25.12+ / `apk` environment
- OpenWrt 23.05.x / 22.03.x
- Third-party firmware or stripped-down firmware

---

## Function description

| plug-in | Support content | Description |
|------|----------|------|
| OpenClash | Installation / update / Core installation / Uninstall / Update detection | automatic recognition Meta / Smart Meta Kernel |
| PassWall | Installation / update / Uninstall / Update detection | support `opkg`;OpenWrt 25.12+ Next try to install the upstream `.apk` build |
| PassWall2 | Installation / update / Uninstall / Update detection | support `opkg`;OpenWrt 25.12+ Next try to install the upstream `.apk` build |
| Nikki | Installation / update / Uninstall / Update detection | need `firewall4/nftables` |
| SmartDNS | Installation / update / Uninstall / Update detection | Use official GitHub Release package |
| MosDNS | Installation / update / Uninstall / Update detection | use `sbwml/luci-app-mosdns` GitHub Release package |

---

## OpenWrt 25.12+ / apk Description

OpenWrt 25.12+ use `apk` Package manager, this project has been adapted simultaneously:

- Installation / update
- Check for updates
- Uninstall

PassWall / PassWall2 in 25.12+ I will try to install the upstream next `.apk` Build, actual availability depends on whether the upstream releases the corresponding architecture package.

---

## Important note

- Recommended OpenWrt / iStoreOS / ImmortalWrt 24.x and above, the overall stability is higher.
- Lower versions, modified firmware, and streamlined firmware may encounter dependencies or software source incompatibilities.
- OpenWrt 25.12+ of `apk` The environment has been basically adapted, but it may still be affected by upstream packages.
- Nikki Not supported `iptables` Firewall stack, required `firewall4/nftables`.
- SmartDNS Just install the program and LuCI interface, does not automatically take over or rewrite DNS configuration.
- MosDNS Only install the program,LuCI Interface and upstream Release The basic data package in the package is not automatically taken over or rewritten. DNS configuration.
- The default uninstallation method is safe uninstallation, which only removes the main package and corresponding configuration, and does not perform radical cleanup.

---

## File description

| File | function |
|------|------|
| `menu.sh` | Unified menu entry |
| `install.sh` | OpenClash Installation / update |
| `update.sh` | OpenClash Quick update entry |
| `repair.sh` | OpenClash Basic repair |
| `passwall.sh` | PassWall Installation / update |
| `passwall2.sh` | PassWall2 Installation / update |
| `nikki.sh` | Nikki Installation / update |
| `smartdns.sh` | SmartDNS Installation / update |
| `mosdns.sh` | MosDNS Installation / update |
| `check-updates.sh` | Check for plugin updates |
| `uninstall.sh` | Safely uninstall plugins |
| `auto-download-pro.sh` | Old portal compatibility wrapper, forwarded to `passwall.sh` |
| `test-auto-download.sh` | The old test entry compatibility wrapper has been forwarded to `passwall.sh` |

---

## Acknowledgments

- OpenClash: <https://github.com/vernesong/OpenClash>
- PassWall: <https://github.com/Openwrt-Passwall/openwrt-passwall>
- PassWall2: <https://github.com/Openwrt-Passwall/openwrt-passwall2>
- Nikki: <https://github.com/nikkinikki-org/OpenWrt-nikki>
- SmartDNS: <https://github.com/pymumu/smartdns>
- MosDNS LuCI: <https://github.com/sbwml/luci-app-mosdns>
