#!/bin/bash
#
# build-iso.sh — Build a reproducible macOS-Lite ISO.
# Uses kernel/initrd from the host container (Debian bookworm).
#
# Usage: ./scripts/build-iso.sh [variant]
#   variant: "" (default, DFSG-free) | "nonfree-firmware"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
OUTPUT_DIR="$ROOT_DIR/build/image"
DATESTAMP="$(date -u +%Y%m%d)"
VARIANT="${1:-default}"

echo "=== macOS-Lite ISO build ==="
echo "Variant: $VARIANT"
echo "Date:    $(date -u)"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ---- Find kernel and initrd in host container ----
echo "=== Finding kernel in container ==="
KERNEL=$(ls /boot/vmlinuz-*amd64 2>/dev/null | head -1)
INITRD=$(ls /boot/initrd.img-*amd64 2>/dev/null | head -1)

if [ -z "$KERNEL" ] || [ -z "$INITRD" ]; then
    echo "ERROR: No kernel/initrd found in /boot" >&2
    ls -la /boot/ 2>/dev/null || echo "  (no /boot directory)" >&2
    exit 1
fi
echo "Kernel: $(basename "$KERNEL")"
echo "Initrd: $(basename "$INITRD")"

# ---- Create ISO directory structure ----
echo "=== Creating ISO structure ==="
ISO_DIR="$OUTPUT_DIR/iso"
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR/boot/grub"

cp "$KERNEL" "$ISO_DIR/boot/vmlinuz"
cp "$INITRD" "$ISO_DIR/boot/initrd.img"

cat > "$ISO_DIR/boot/grub/grub.cfg" <<'GRUBCFG'
set default=0
set timeout=5
set gfxmode=auto
load_video
insmod gfxterm
menuentry "macOS-Lite (live)" {
    linux /boot/vmlinuz boot=live components quiet splash
    initrd /boot/initrd.img
}
menuentry "Shut down" {
    halt
}
GRUBCFG

# ---- Create ISO with grub-mkrescue ----
echo "=== Creating ISO with grub-mkrescue ==="
grub-mkrescue \
    -o "$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" \
    "$ISO_DIR" || {
    echo "ERROR: grub-mkrescue failed" >&2
    exit 1
}

# ---- Verify ISO ----
ISO_FILE="$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso"
if [ ! -f "$ISO_FILE" ]; then
    echo "ERROR: ISO file was not created" >&2
    exit 1
fi

ISO_SIZE=$(du -b "$ISO_FILE" | cut -f1)
echo "ISO size: $ISO_SIZE bytes ($(du -h "$ISO_FILE" | cut -f1))"

if [ "$ISO_SIZE" -lt 1000000 ]; then
    echo "ERROR: ISO too small ($ISO_SIZE bytes)" >&2
    exit 1
fi

cd "$OUTPUT_DIR"
sha256sum "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" \
    > "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso.sha256"

echo ""
echo "=== BUILD SUCCESSFUL ==="
echo "ISO: $ISO_FILE"
echo "Size: $(du -h "$ISO_FILE" | cut -f1)"
