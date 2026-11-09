#!/bin/bash
#
# build-iso.sh — Build a reproducible macOS-Lite ISO.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
OUTPUT_DIR="$ROOT_DIR/build/image"
DATESTAMP="$(date -u +%Y%m%d)"
VARIANT="${1:-default}"
BUILD_LOG="$OUTPUT_DIR/build.log"

SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"
export SOURCE_DATE_EPOCH
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

echo "=== macOS-Lite ISO build ==="
echo "Variant: $VARIANT"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

exec > >(tee -a "$BUILD_LOG") 2>&1

# ---- Prerequisites ----
echo "=== Prerequisites ==="
for cmd in debootstrap curl dpkg grub-mkrescue xorriso; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "MISSING: $cmd" >&2; exit 1; }
    echo "OK: $cmd"
done

# ---- Create chroot with kernel included ----
echo "=== Creating chroot with debootstrap ==="
CHROOT_DIR="/tmp/macos-lite-chroot"
rm -rf "$CHROOT_DIR"
mkdir -p "$CHROOT_DIR"

debootstrap --no-verify-gpg \
    --variant=minimal \
    --arch=amd64 \
    --include=linux-image-amd64,grub-pc,grub-efi-amd64 \
    bookworm "$CHROOT_DIR" \
    http://deb.debian.org/debian/ || {
    echo "ERROR: debootstrap failed" >&2
    exit 1
}

if [ ! -f "$CHROOT_DIR/bin/bash" ]; then
    echo "ERROR: Chroot missing /bin/bash" >&2
    exit 1
fi
echo "Chroot base OK"

# ---- Copy custom files ----
echo "=== Copying custom files ==="
cp -a "$CONFIG_DIR/includes.chroot/." "$CHROOT_DIR/"

# ---- Verify kernel ----
KERNEL=$(ls "$CHROOT_DIR/boot/vmlinuz-*amd64" 2>/dev/null | head -1)
INITRD=$(ls "$CHROOT_DIR/boot/initrd.img-*amd64" 2>/dev/null | head -1)
if [ -z "$KERNEL" ] || [ -z "$INITRD" ]; then
    echo "ERROR: No kernel/initrd in chroot" >&2
    ls -la "$CHROOT_DIR/boot/" 2>/dev/null || echo "  (no /boot)" >&2
    exit 1
fi
echo "Kernel: $(basename "$KERNEL")"
echo "Initrd: $(basename "$INITRD")"

# ---- Create ISO ----
echo "=== Creating ISO ==="
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

grub-mkrescue \
    -o "$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" \
    "$ISO_DIR" || {
    echo "ERROR: grub-mkrescue failed" >&2
    exit 1
}

# ---- Verify ----
ISO_FILE="$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso"
if [ ! -f "$ISO_FILE" ]; then
    echo "ERROR: ISO not created" >&2
    exit 1
fi

ISO_SIZE=$(du -b "$ISO_FILE" | cut -f1)
echo "ISO size: $ISO_SIZE bytes"

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
