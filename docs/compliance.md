# Compliance — GPL/licensing checklist & asset license report

macOS-Lite is built entirely from Free and Open Source Software. This document
is the licensing checklist and the asset license report that must accompany
every release.

---

## A. Source code licensing (software)

| Component | License | Source | Notes |
|-----------|---------|--------|-------|
| Linux kernel | GPL-2.0 | Debian `linux-image-amd64` | Kernel module firmware may be separate |
| Debian base / GNU tools | GPL / LGPL / various DFSG | Debian `bookworm main` | DFSG-free by default |
| live-build (build tool) | GPL-2.0 | Debian `live-build` | Build-time only, not shipped |
| Wayfire | MIT | Debian `wayfire` | Compositor |
| wlroots | MIT | upstream | Wayfire dependency |
| plank | GPL-3.0 | Debian `plank` | Dock |
| dunst | BSD-style | Debian `dunst` | Notifications |
| wofi | MIT/GPL | Debian `wofi` | Launcher (Spotlight-like) |
| PipeWire | MIT | Debian `pipewire` | Audio |
| NetworkManager | GPL-2.0 | Debian `network-manager` | Networking |
| seatd / elogind | MIT / LGPL | Debian | Seat management |
| GTK4 | LGPL-2.1+ | Debian `gtk4` | Shell toolkit |
| Calamares | GPL-3.0 | Debian `calamares` | Installer (optional) |
| firefox-esr | MPL-2.0 | Debian `firefox-esr` | Browser (optional) |
| foot | MIT | Debian `foot` | Terminal |
| thunar | GPL-2.0 | Debian `thunar` | File manager |
| gedit | GPL-2.0 | Debian `gedit` | Text editor |
| Custom `mlite-*` shell | MIT (this repo) | `src/` | Our original code |

### Checklist for every release

- [ ] All packages installed come from Debian `bookworm` main (DFSG-free) by default.
- [ ] `contrib`/`non-free-firmware` is opt-in (separate variant ISO) and clearly labelled.
- [ ] `debian/copyright` files reviewed for every `mlite-*` package we build.
- [ ] GPL/LGPL source code made available on request (written offer) for GPL components we distribute (kernel, plank, etc.).
- [ ] No Apple code, frameworks, or binaries are used or linked.
- [ ] No Apple trademarks (Apple, macOS, SF Pro, Dock, Control Center, Spotlight as product names) are claimed in branding.
- [ ] GPG signatures produced with project key; public key published with releases.

### Source-offer (GPL) text (include with release)

> macOS-Lite includes software licensed under the GNU General Public License.
> Corresponding source code is available for a period of at least three (3)
> years from the date of distribution, at no more than the cost of physical
> distribution, by contacting the macOS-Lite project or by downloading from
> the repository at https://github.com/<org>/macos-lite-distro.

---

## B. Asset license report (theming)

| Asset | Source | License | Use in macOS-Lite |
|-------|--------|---------|-------------------|
| Inter font | rsms/inter | SIL Open Font License 1.1 | System UI font |
| JetBrains Mono font | JetBrains/jetbrains-mono | SIL Open Font License 1.1 | Monospace / code |
| Papirus icon theme | PapirusDevelopmentTeam/papirus-icon-theme | CC0 / CC-BY-3.0 (mixed) | Default icons (adapted) |
| Original wallpapers | macOS-Lite project (original) | CC0 1.0 | Desktop + GRUB background |
| Original dock theme (plank) | macOS-Lite project (original) | CC0 1.0 | Plank dock theme |
| Original shell icons (mlite-*) | macOS-Lite project (original) | MIT | Top bar / launcher icons |
| GRUB background | derived from wallpaper | CC0 1.0 | Boot menu |

**Assets NOT used (to avoid trademark/art infringement):**
- Apple SF Pro / San Francisco font
- Apple emoji / icon artwork
- macOS wallpapers (photography)
- The "" Apple logo
- The word "Dock" as a product/trade-dress claim

Full asset inventory with hashes and licenses is generated at release time:

```bash
# Example: generate asset license report
find assets -type f -exec sha256sum {} + > assets/ASSET-SHA256.txt
cat assets/ASSET-LICENSES.md  # this document section B
```

See `assets/ASSET-LICENSES.md` (to be populated with the actual bundled files).

---

## C. Trademark statement

"macOS-Lite" is a descriptive project name meaning "a lightweight, macOS-like
desktop on Linux." It is not affiliated with, endorsed by, or connected to Apple
Inc. macOS is a trademark of Apple Inc. All third-party trademarks are the
property of their respective owners.

If the project is released publicly, we recommend:
1. Conducting a trademark clearance search for "macOS-Lite."
2. Considering an original brand name (e.g., "LiteDesk", "Horizon OS") to
   avoid any risk.
3. Never using Apple logos, SF Pro, or "macOS" as a product name in marketing.

---

## D. Repository structure

```
macos-lite-distro/
├── README.md                       # project overview + quick start
├── LICENSE                         # MIT (project code)
├── docs/
│   ├── architecture.md             # base distro + stack + trade-offs
│   ├── desktop-stack.md            # reproducing macOS interactions
│   ├── requirements-performance.md # HW targets + service tuning
│   ├── packaging-build.md          # live-build + package lists + reproducible
│   ├── ci-cd.md                    # GitHub Actions strategy (this file's twin)
│   ├── compliance.md               # GPL checklist + asset license report
│   └── install.md                  # user-facing install & update docs
├── config/                         # live-build chroot/binary config
│   ├── archives/                   # apt sources
│   ├── bootloaders/                # grub BIOS/UEFI configs
│   ├── hooks/                      # live-build hooks (tuning, desktop, cleanup)
│   ├── includes.chroot/            # files into the live rootfs
│   ├── includes.binary/            # files into the ISO
│   └── package-lists/              # .list package selections
├── scripts/                        # build-iso.sh, qemu-smoke.sh, sign-release.sh
├── assets/                         # icons, fonts, wallpapers (license-free)
├── tests/                          # QEMU acceptance tests
└── .github/workflows/
    └── build-release.yml           # CI: build, sign, smoke test, release
```
