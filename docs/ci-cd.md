# CI/CD — GitHub Actions strategy for reproducible ISO builds

File: `.github/workflows/build-release.yml`

## Overview

The pipeline builds, signs, smoke-tests, and releases macOS-Lite ISOs entirely
on GitHub Actions, using Debian `bookworm` containers for a clean, identical
build environment every time.

## Workflow jobs

| Job | Runs on | Purpose |
|-----|---------|---------|
| `build` | `ubuntu-latest` + `debian:bookworm` container | Builds the ISO with `live-build` (matrix: variant × arch) |
| `sign` | `ubuntu-latest` + `debian:bookworm` container | GPG-signs ISO + checksums (tag pushes only) |
| `smoke-test` | `ubuntu-latest` + `debian:bookworm` container | QEMU boot-to-desktop test per variant |
| `release` | `ubuntu-latest` | Creates GitHub Release and attaches signed artifacts |

## Build matrix

```
variant:      default   | nonfree-firmware
architecture: amd64     | amd64
```

- `default` = DFSG-free only (no proprietary firmware).
- `nonfree-firmware` = includes `firmware-*` packages for Wi-Fi/GPU.

Fail-fast is disabled so one variant's failure doesn't cancel the other.

## Reproducibility

- `SOURCE_DATE_EPOCH` is pinned (default `1700000000`, overridden to the tag's
  commit date on tag pushes).
- `live-build` normalizes chroot file mtimes; SquashFS uses deterministic
  `xz` options (`-Xbcj x86 -b 1M`).
- Build container is pinned to `debian:bookworm`; apt sources pinned to
  `bookworm` + `bookworm-security` (no rolling `updates`).
- Consumers can rebuild and compare SHA-256 of the ISO to verify.

## Caching & incremental builds

| Cache | Key | Restore keys |
|-------|-----|--------------|
| apt package cache (`/var/cache/apt/archives`) | `apt-{variant}-{hash(archives/*.list)}` | `apt-{variant}-` |
| ccache (`/root/.ccache`) | `ccache-{variant}-{sha}` | `ccache-{variant}-` |

The apt cache speeds repeated builds by reusing downloaded `.deb` files. The
binary package list hash in the key invalidates the cache when package
selection changes.

## Secrets handling

| Secret | Used by | Purpose |
|--------|---------|---------|
| `MACOS_LITE_GPG_PRIVATE_KEY` | `sign` | ASCII-armored GPG private key for release signing |
| `MACOS_LITE_GPG_PASSPHRASE` | `sign` | Passphrase for the GPG key (if any) |
| `GITHUB_TOKEN` | `release` | Auto-provided; creates GitHub Release & uploads assets |

The GPG key is imported with `gpg --import --batch --yes` inside the container
and never written to the workflow file. If the secret is absent, signing is
skipped and the job continues (unsigned artifacts), so PRs from forks still
build/test.

## Artifacts

- `build-logs-{variant}` — live-build logs + checksums (7 days)
- `macos-lite-unsigned-{variant}-amd64` — ISO before signing (7 days)
- `macos-lite-signed-{tag}` — ISO + `.sha256` + `.sig` files (30 days)
- `smoke-result-{variant}` — JSON result of QEMU test (7 days)

Signed artifacts are consumed by the `release` job and attached to the GitHub
Release.

## QEMU smoke test (gating)

Each built ISO is booted in QEMU (`qemu-system-x86_64`, KVM if available else
TCG) with 2 GB RAM / 2 vCPUs. The test:

1. Boots the ISO.
2. Polls the serial console for Wayfire / bar / login evidence.
3. Records boot time and writes `smoke-result.json` (`passed`/`failed`).
4. Takes a best-effort PNG screenshot.

Any smoke-test failure fails the job and blocks the release. Baseline boot
time and idle RAM are recorded for regression tracking.

## Release creation

On a git tag matching `v*`:

1. `sign` job produces signed ISO/checksums.
2. `smoke-test` must pass for all variants.
3. `release` job creates (or updates) a GitHub Release at the tag, attaches
   all signed assets, and publishes a release body with verification
   instructions (GPG + SHA-256).

## Local replication

```bash
# Build locally (same flags as CI)
./scripts/build-iso.sh default

# Sign
./scripts/sign-release.sh build/image/macos-lite-default-amd64-*.iso macos-lite-release

# Smoke test
./scripts/qemu-smoke.sh build/image/macos-lite-default-amd64-*.iso
```

## Security notes

- Workflow uses `actions/checkout@v4` with `fetch-depth: 0` so tags are
  available for versioning.
- `GITHUB_TOKEN` has `contents: write` only on the `release` job (tag pushes).
- No build secrets are logged; GPG passphrase is never echoed.
- Container runs as root (required for live-build/debootstrap) but only within
  the ephemeral CI container.
