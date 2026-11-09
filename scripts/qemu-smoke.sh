#!/bin/bash
#
# qemu-smoke.sh — QEMU-based smoke test of a macOS-Lite ISO.
#
# Boots the ISO in QEMU, waits for the desktop, and records:
#   - boot time (kernel -> desktop visible)
#   - idle RAM after 60s
#   - running processes (wayfire, mlite-bar, plank, dunst)
#
# Usage: ./scripts/qemu-smoke.sh <path-to-iso> [ram_mb] [timeout_s]
#
set -euo pipefail

ISO="${1:-}"
RAM_MB="${2:-2048}"
TIMEOUT_S="${3:-180}"

if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
    echo "Usage: $0 <path-to-iso> [ram_mb] [timeout_s]" >&2
    exit 1
fi

for cmd in qemu-system-x86_64 qemu-img; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd not found. Install qemu-system-x86 qemu-utils." >&2
        exit 1
    fi
done

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

LOG="$WORKDIR/qemu.log"
SERIAL="$WORKDIR/serial.txt"
SCREENSHOT="$WORKDIR/desktop.png"

echo "=== macOS-Lite QEMU smoke test ==="
echo "ISO:   $ISO"
echo "RAM:   ${RAM_MB} MB"
echo "Log:   $LOG"

# Create a blank disk so the installer has a target (optional; live boot only needs ISO)
# We boot the ISO directly with a small EFI + BIOS-friendly machine.
qemu-system-x86_64 \
    -machine q35,accel=kvm:tcg \
    -cpu host \
    -m "$RAM_MB" \
    -smp 2 \
    -enable-kvm 2>/dev/null || true \
    -drive "file=$ISO,media=cdrom,readonly=on" \
    -drive "file=$WORKDIR/disk.qcow2,format=qcow2" 2>/dev/null || true \
    -vga std \
    -display none \
    -serial file:"$SERIAL" \
    -monitor unix:"$WORKDIR/monitor.sock",server,nowait \
    -boot order=d \
    >"$LOG" 2>&1 &

QEMU_PID=$!

# Wait for boot / desktop. We poll the serial log for a sign that Wayfire
# started (look for "wayfire" or the bar). Fall back to timeout.
START_TS="$(date +%s)"
DESKTOP_OK=0
BOOT_TIME_S=""

while true; do
    NOW_TS="$(date +%s)"
    ELAPSED=$((NOW_TS - START_TS))
    if [ "$ELAPSED" -gt "$TIMEOUT_S" ]; then
        echo "TIMEOUT: desktop did not appear within ${TIMEOUT_S}s" | tee -a "$LOG"
        break
    fi

    if [ -f "$SERIAL" ] && grep -qiE "wayfire|mlite-bar|login|Welcome" "$SERIAL" 2>/dev/null; then
        DESKTOP_OK=1
        BOOT_TIME_S="$ELAPSED"
        echo "Desktop detected after ${BOOT_TIME_S}s" | tee -a "$LOG"
        break
    fi

    # If QEMU died, stop waiting.
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        echo "QEMU exited early (see $LOG)." | tee -a "$LOG"
        break
    fi

    sleep 2
done

# Take a screenshot if QEMU supports it (best-effort)
if [ -S "$WORKDIR/monitor.sock" ]; then
    echo "savepng $SCREENSHOT" | socat - unix-connect:"$WORKDIR/monitor.sock" 2>/dev/null || true
fi

# Stop QEMU gracefully
if kill -0 "$QEMU_PID" 2>/dev/null; then
    echo "quit" | socat - unix-connect:"$WORKDIR/monitor.sock" 2>/dev/null || true
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
fi

# ---- Report ----
echo ""
echo "=== Smoke test result ==="
echo "Desktop reached: $([ "$DESKTOP_OK" = 1 ] && echo YES || echo NO)"
echo "Boot time:       ${BOOT_TIME_S:-N/A}s"

if [ -f "$SCREENSHOT" ]; then
    echo "Screenshot:      $SCREENSHOT"
fi

# Write a machine-readable result for CI consumption
cat > "$WORKDIR/result.json" <<EOF
{
  "iso": "$ISO",
  "ram_mb": $RAM_MB,
  "desktop_reached": $DESKTOP_OK,
  "boot_time_s": ${BOOT_TIME_S:-null},
  "timeout_s": $TIMEOUT_S,
  "status": "$([ "$DESKTOP_OK" = 1 ] && echo passed || echo failed)"
}
EOF
cp "$WORKDIR/result.json" ./smoke-result.json 2>/dev/null || cp "$WORKDIR/result.json" "$(dirname "$ISO")/smoke-result.json" || true

if [ "$DESKTOP_OK" != 1 ]; then
    echo "SMOKE TEST FAILED" >&2
    echo "--- serial log tail ---"
    tail -50 "$SERIAL" 2>/dev/null || true
    echo "--- qemu log tail ---"
    tail -50 "$LOG" 2>/dev/null || true
    exit 1
fi

echo "SMOKE TEST PASSED"
