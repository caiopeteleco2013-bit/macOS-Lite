#!/bin/bash
#
# build-iso.sh — Build a reproducible macOS-Lite ISO with live-build.
#
# Usage: ./scripts/build-iso.sh [variant]
#   variant: "" (default, DFSG-free) | "nonfree-firmware"
#
# Requires (Debian/Ubuntu host):
#   live-build debootstrap git xorriso squashfs-tools grub-pc-bin \
#   grub-efi-amd64-bin mtools e2fsprogs
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
OUTPUT_DIR="$ROOT_DIR/build/image"
DATESTAMP="$(date -u +%Y%m%d)"
VARIANT="${1:-default}"

# ---- Reproducibility: fixed source date epoch ----
# Use the release tag date if available, otherwise a fixed point.
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"
export SOURCE_DATE_EPOCH
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

echo "=== macOS-Lite ISO build ==="
echo "Root:        $ROOT_DIR"
echo "Variant:     $VARIANT"
echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"

# ---- Prerequisite check ----
for cmd in live-build lb debootstrap xorriso mksquashfs grub-mkrescue; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $cmd" >&2
        echo "Install: sudo apt-get install live-build debootstrap xorriso squashfs-tools grub-pc-bin grub-efi-amd64-bin mtools e2fsprogs" >&2
        exit 1
    fi
done

# ---- Clean previous build artifacts ----
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ---- Select live-build config ----
# Default config is DFSG-free (no non-free firmware). The nonfree variant adds
# firmware archives for Wi-Fi/GPU out-of-the-box support.
case "$VARIANT" in
    default)
        echo "Building DFSG-free variant (no non-free firmware by default)."
        ;;
    nonfree-firmware)
        echo "Building nonfree-firmware variant."
        cp -a "$CONFIG_DIR/archives/debian.list.chroot" "$CONFIG_DIR/archives/debian.list.chroot.bak"
        cat > "$CONFIG_DIR/archives/debian.list.chroot" <<EOF
deb https://deb.debian.org/debian/ bookworm main contrib non-free-firmware
deb https://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb https://deb.debian.org/debian/ bookworm-updates main contrib non-free-firmware
EOF
        ;;
    *)
        echo "ERROR: unknown variant '$VARIANT'. Use 'default' or 'nonfree-firmware'." >&2
        exit 1
        ;;
esac

# ---- Stage shell source into the chroot (so hooks can install it) ----
STAGE_DIR="$CONFIG_DIR/includes.chroot/opt/macos-lite/src"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
if [ -d "$ROOT_DIR/src" ]; then
    cp -a "$ROOT_DIR/src/." "$STAGE_DIR/"
    echo "Staged shell source into $STAGE_DIR"
fi

# ---- Configure live-build ----
cd "$ROOT_DIR"
lb clean --binary --chroot 2>/dev/null || true

# Optional GRUB background: only pass --grub-splash if the file exists.
GRUB_SPLASH_ARGS=()
if [ -f "$ROOT_DIR/assets/wallpapers/grub-bg.png" ]; then
    GRUB_SPLASH_ARGS=(--grub-splash "$ROOT_DIR/assets/wallpapers/grub-bg.png")
    echo "Using GRUB background: assets/wallpapers/grub-bg.png"
else
    echo "Note: assets/wallpapers/grub-bg.png not found; building without GRUB splash."
fi

LB_ARGS=(
    --architectures amd64
    --linux-flavours amd64
    --mode debian
    --distribution bookworm
    --archive-areas "main contrib non-free-firmware"
    --bootappend-live "boot=live components quiet splash"
    --bootloader grub
    "${GRUB_SPLASH_ARGS[@]}"
    --iso-application "macOS-Lite"
    --iso-publisher "macOS-Lite Project"
    --iso-volume "macOS-Lite-$DATESTAMP"
    --memtest none
    --security true
    --updates true
    --backports false
    --source false
    --firmware-chroot false
    --firmware-binary false
    --compression xz
    --xorriso-boot-grub-device-hd0 /dev/sda
)

lb config "${LB_ARGS[@]}" "${@:2}"

# ---- Build the ISO ----
echo "Building live image (this may take a while)..."
lb build

# ---- Locate produced ISO ----
ISO_PATH=""
for f in "$ROOT_DIR"/*.iso "$OUTPUT_DIR"/*.iso; do
    if [ -f "$f" ]; then
        ISO_PATH="$f"
        break
    fi
done

if [ -z "$ISO_PATH" ] || [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: no ISO produced." >&2
    exit 1
fi

ISO_NAME="$(basename "$ISO_PATH")"
FINAL_ISO="$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso"

echo "Copying ISO to $FINAL_ISO"
cp "$ISO_PATH" "$FINAL_ISO"

# ---- Generate checksums ----
cd "$OUTPUT_DIR"
sha256sum "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" \
    > "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso.sha256"

echo ""
echo "=== Build complete ==="
echo "ISO:       $FINAL_ISO"
echo "SHA256:    $FINAL_ISO.sha256"
echo "Size:      $(du -h "$FINAL_ISO" | cut -f1)"
echo ""
echo "Next: sign with scripts/sign-release.sh, then test with scripts/qemu-smoke.sh"

# ---- Restore archives if we modified them for nonfree variant ----
if [ "$VARIANT" = "nonfree-firmware" ] && [ -f "$CONFIG_DIR/archives/debian.list.chroot.bak" ]; then
    mv "$CONFIG_DIR/archives/debian.list.chroot.bak" "$CONFIG_DIR/archives/debian.list.chroot"
fi
