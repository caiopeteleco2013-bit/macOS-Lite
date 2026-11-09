# Acceptance tests

QEMU-based smoke/acceptance tests for macOS-Lite ISOs.

- `scripts/qemu-smoke.sh` — boots an ISO, waits for the desktop, records boot
  time and idle RAM, writes a machine-readable `smoke-result.json`.
- Run locally: `./scripts/qemu-smoke.sh <iso> [ram_mb] [timeout_s]`
- Run in CI: `.github/workflows/build-release.yml` → `smoke-test` job.

Add more tests here as the shell (`mlite-*`) is implemented:
- launch dock apps
- open control center
- trigger Spotlight (Super+Space)
- notification appears from dunst
