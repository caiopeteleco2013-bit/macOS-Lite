# macOS-Lite — A lightweight, macOS-inspired desktop OS on Linux

**macOS-Lite** is a reference implementation plan and build system for a
macOS-inspired desktop operating system built on the Linux kernel. It targets a
clean, visually polished, extremely lightweight desktop experience with
macOS-style interactions (dock, top bar, control center, notification center,
Spotlight-like search, fluid animations) — without using any Apple trademarks,
art assets, or proprietary code.

## Goals

| Goal | Target |
|------|--------|
| Base | Debian Stable (minimal) |
| Idle RAM | ≤ 600 MB (target ~400–500 MB) |
| Boot to desktop | ≤ 15 s on modest hardware, ≤ 8 s on SSD |
| CPU at idle | < 5 % on a modern dual-core |
| ISO size | < 1.2 GB |
| Reproducible builds | Yes (via GitHub Actions + live-build) |

## What this repository contains

- `docs/` — Design & implementation plan (architecture, desktop stack, requirements,
  packaging, CI/CD, compliance, install/update docs).
- `config/` — Debian `live-build` chroot configuration (archives, hooks, package
  lists, files shipped into the image).
- `scripts/` — Build, signing, QEMU smoke-test, and release helper scripts.
- `.github/workflows/` — GitHub Actions CI for reproducible ISO builds, signing,
  QEMU smoke tests, and releases.
- `assets/` — License-free theming assets (icons, fonts, wallpapers) placeholders.
- `tests/` — QEMU-based acceptance tests.

## Quick start (local build)

```bash
# 1. Install build dependencies (Debian/Ubuntu host)
sudo apt-get install -y live-build debootstrap git xorriso squashfs-tools \
    grub-pc-bin grub-efi-amd64-bin mtools e2fsprogs

# 2. Build the ISO
./scripts/build-iso.sh

# 3. Smoke test in QEMU
./scripts/qemu-smoke.sh build/image/macos-lite-amd64.iso
```

## CI

Pushes to `main` and tags trigger a GitHub Actions workflow that:

1. Builds the ISO reproducibly with `live-build` in a Docker/container environment.
2. Signs the ISO + SHA256SUMS with a project GPG key (secret).
3. Runs QEMU-based smoke tests (boot to desktop, login, basic apps).
4. Creates a GitHub Release and attaches the signed ISO, checksums, and signature.

See `.github/workflows/build-release.yml` and `docs/ci-cd.md`.

## Licensing

Built entirely from Free Software. Debian main + a small set of GPL/MIT/BSD
third-party components. All theming assets are license-free or openly licensed.
See `docs/compliance.md` for the GPL/licensing checklist and asset license
report.

## Status

**Planning / reference implementation.** The configs and scripts are written to
be runnable on a Debian-based build host. No Apple code or assets are used.
