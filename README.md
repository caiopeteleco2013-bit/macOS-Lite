# macOS-Lite — lightweight, macOS-inspired desktop OS on Linux

**macOS-Lite** is a complete, buildable reference implementation of a
macOS-inspired desktop operating system on the Linux kernel. It provides a
visually polished, extremely lightweight desktop with macOS-like interactions
(top bar, dock, Spotlight-like search, Control Center, Notification Center,
fluid animations, gestures) — using only Free Software and **no Apple code,
fonts, icons, or artwork**.

## Interface (working code in `src/`)

| Component | Trigger | macOS equivalent |
|-----------|---------|------------------|
| **Top bar** (`mlite-bar`) | Always on | Menu bar |
| **Spotlight launcher** (`mlite-launcher`) | Super + Space | Spotlight |
| **Control Center** (`mlite-control-center`) | Super + Shift + Space | Control Center |
| **Notification Center** (`mlite-notification-center`) | Click time / Super + C | Notification Center |
| **Dock** (plank + `macos-lite` theme) | Always on | Dock |
| **Compositor** (Wayfire) | Window mgmt + animations | WindowServer |

See `docs/interface.md` for the full interface specification.

## Goals

| Goal | Target |
|------|--------|
| Base | Debian Stable (minimal) |
| Idle RAM | ≤ 600 MB (target ~400–500 MB) |
| Boot to desktop | ≤ 15 s (modest), ≤ 8 s (SSD) |
| CPU at idle | < 5 % on dual-core |
| ISO size | < 1.2 GB |
| Reproducible builds | Yes (live-build + GitHub Actions) |

## Repository contents

```
README.md               project overview + quick start
LICENSE                 MIT (project code)
docs/                   architecture, desktop-stack, interface, requirements,
                        packaging-build, ci-cd, compliance, install
config/                 live-build chroot/binary config (archives, bootloaders,
                        hooks, package-lists, includes.chroot, includes.binary)
scripts/                build-iso.sh, qemu-smoke.sh, sign-release.sh
src/                    mlite-bar, mlite-launcher, mlite-control-center,
                        mlite-notification-center, common theme
tests/                  QEMU acceptance test README
.github/workflows/      build-release.yml (reproducible CI/CD)
assets/                 ASSET-LICENSES.md + placeholder dirs
```

## Quick start (local build)

```bash
# 1. Install build dependencies (Debian/Ubuntu host)
sudo apt-get install -y live-build debootstrap git xorriso squashfs-tools \
    grub-pc-bin grub-efi-amd64-bin mtools e2fsprogs

# 2. Build the ISO
./scripts/build-iso.sh default

# 3. Sign (requires project GPG key)
./scripts/sign-release.sh build/image/macos-lite-default-amd64-*.iso macos-lite-release

# 4. Smoke test in QEMU
./scripts/qemu-smoke.sh build/image/macos-lite-default-amd64-*.iso
```

## CI

Pushes to `main` and tags trigger `.github/workflows/build-release.yml`:

1. Builds the ISO reproducibly (Debian `bookworm` container, `SOURCE_DATE_EPOCH`).
2. Signs ISO + checksums with project GPG key (secret).
3. QEMU smoke test (boot to desktop, idle RAM, processes).
4. Creates a GitHub Release with signed ISO, checksums, and signatures.

## Licensing

Project code: MIT. Shell components are original. All theming assets are
license-free or openly licensed (Inter/JetBrains Mono SIL OFL, Papirus CC0/
CC-BY, original CC0 wallpapers). No Apple IP. See `docs/compliance.md`.

## Status

**Working reference implementation.** Interface code (GTK4 + LayerShell shell,
Wayfire config, Plank/dunst/wofi themes) is complete and staged into the live
image by `config/hooks/0250-install-shell.hook.chroot`. Build on a Debian host
or via GitHub Actions.
