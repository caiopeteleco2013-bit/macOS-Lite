# Minimal system requirements & performance goals

## Hardware requirements

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| Architecture | x86_64 | x86_64 | AMD64 only initially |
| CPU | Dual-core 1.5 GHz (x86_64) | Quad-core 2.4 GHz+ | Wayland + wlroots needs SSE2+ |
| RAM | 2 GB | 4 GB | Idle target ≤ 600 MB |
| Storage | 16 GB | 32 GB+ SSD | ISO < 1.2 GB; install ~5 GB |
| GPU | Intel HD/AMD GCN/NVIDIA (EGLStream) | Intel UHD 620+ / AMD / NVIDIA | wlroots-compatible, no proprietary GL required for basic |
| Display | 720p | 1080p / HiDPI | Wayfire fractional scaling supported |

## Performance goals

| Metric | Target | How measured |
|--------|--------|--------------|
| Boot to desktop (SSD) | ≤ 8 s | `systemd-analyze blame` / QEMU timestamp |
| Boot to desktop (HDD) | ≤ 15 s | same |
| Idle RAM | ≤ 600 MB (target ~450 MB) | `free -m` after 5 min idle |
| Idle CPU | < 5 % (2-core) | `top`/`mpstat` average |
| UI frame rate | 60 fps steady | Wayfire damage events / `mangohud` |
| App launch (terminal) | < 400 ms | `time foot` cold start |
| ISO size | < 1.2 GB | `ls -lh` on output ISO |
| Shutdown | < 3 s | `systemd-analyze` |

## Service tuning to minimize memory/CPU

Applied in `config/includes.chroot/etc/systemd/` and via `live-build` hooks.

### Disabled / masked services (default install)

```text
bluetooth.service            (opt-in; hardware may not exist)
cups.service                 (printing opt-in)
ModemManager.service         (no modem by default)
avahi-daemon.service         (no zeroconf needed on minimal desktop)
rsyslog.service              (journald handles logging)
unattended-upgrades.service  (manual/security updates only to avoid background churn)
preload.service              (not used; wastes RAM)
```

Masked units (never start):
```text
network-manager-wait-online.service   # don't block boot on network
systemd-networkd-wait-online.service
```

### journald limits

`/etc/systemd/journald.conf`:
```ini
[Journal]
Storage=auto
Compress=yes
SystemMaxUse=50M
SystemKeepFree=100M
MaxRetentionSec=7day
MaxFileSec=1day
```

### zram (compressed RAM swap)

`/etc/systemd/zram-generator.conf`:
```ini
[zram0]
zram-size = min(ram, 4096)
compression-algorithm = zstd
```

### Kernel/sysctl tuning

`/etc/sysctl.d/99-macos-lite.conf`:
```ini
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
```

### Wayfire power/perf

- `vsync = true` in `[core]`.
- Effects (`wobbly`, `dim`) disabled on battery via a `udev`/`systemd` hook reading `/sys/class/power_supply/*/online`.

### Boot measurement (in CI smoke test)

```bash
systemd-analyze > boot-plot.txt
systemd-analyze blame | head -20
```

## Verification in CI

The QEMU smoke test (`scripts/qemu-smoke.sh`) boots the ISO, logs in, and records:
- time from kernel boot to Wayfire + bar visible,
- idle RAM after 60 s,
- whether `wayfire`, `mlite-bar`, `plank`, `dunst` processes are running.

Results are uploaded as workflow artifacts and gated: any regression vs. baseline fails the build.
