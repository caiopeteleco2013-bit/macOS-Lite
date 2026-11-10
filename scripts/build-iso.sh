#!/bin/bash
#
# build-iso.sh — Build a macOS-Lite ISO.
# Downloads kernel .deb from Debian pool (containers have no /boot kernel),
# extracts vmlinuz + initrd, builds bootable ISO with grub-mkrescue.
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

# ---- Step 1: Download kernel .deb from Debian pool ----
echo ""
echo "=== [1/4] Downloading linux-image-amd64 from Debian pool ==="
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

KERNEL_PATH=$(curl -fsSL --max-time 60 \
    "http://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages" 2>/dev/null \
    | awk -v RS='' '/^Package: linux-image-amd64$/{match($0,/Filename: ([^\n]+)/,a); print a[1]; exit}')

if [ -z "$KERNEL_PATH" ]; then
    echo "ERROR: linux-image-amd64 not found in Debian Packages index" >&2
    exit 1
fi
echo "Found in archive: $KERNEL_PATH"

curl -fSL --max-time 600 --retry 3 \
    -o "$WORK/linux-image-amd64.deb" \
    "http://deb.debian.org/debian/${KERNEL_PATH}" || {
    echo "ERROR: Failed to download linux-image-amd64.deb" >&2
    exit 1
}
echo "Downloaded: $(du -h "$WORK/linux-image-amd64.deb" | cut -f1)"

# ---- Step 2: Extract kernel and initrd ----
echo ""
echo "=== [2/4] Extracting kernel and initrd ==="
dpkg-deb -x "$WORK/linux-image-amd64.deb" "$WORK/rootfs" || {
    echo "ERROR: dpkg-deb -x failed" >&2
    exit 1
}

KERNEL=$(ls "$WORK/rootfs/boot/vmlinuz-"* 2>/dev/null | head -1)
INITRD=$(ls "$WORK/rootfs/boot/initrd.img-"* 2>/dev/null | head -1)

if [ -z "$KERNEL" ]; then
    echo "ERROR: no vmlinuz found in extracted .deb" >&2
    echo "Boot dir contents:" >&2
    ls -laR "$WORK/rootfs/boot/" 2>/dev/null | head -40 >&2 || true
    exit 1
fi
echo "Kernel: $(basename "$KERNEL")"

# initrd may not exist in the kernel .deb alone — generate one via initramfs-tools
# if missing. Simpler: also grab initramfs-tools + initramfs-tools-core and
# build initrd manually is complex. Instead download the matching initrd from
# the same version's separate package when present; otherwise fall back to a
# minimal initrd from live-boot.
if [ -z "$INITRD" ]; then
    echo "No initrd in kernel .deb — downloading initramfs-tools to generate one"
    # Generate initrd using the kernel's own depmod + initramfs-tools is complex
    # in a bare container. Fallback: download the prebuilt initrd that ships in
    # the Debian installer (netboot initrd, ~30MB, boots to busybox shell).
    NETBOOT_INITRD="http://deb.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
    curl -fSL --max-time 300 -o "$WORK/initrd.gz" "$NETBOOT_INITRD" || {
        echo "ERROR: Failed to download netboot initrd" >&2
        exit 1
    }
    INITRD="$WORK/initrd.gz"
    echo "Using netboot initrd: $(du -h "$INITRD" | cut -f1)"
else
    echo "Initrd: $(basename "$INITRD")"
fi

# ---- Step 3: Build ISO tree ----
echo ""
echo "=== [3/4] Building ISO tree ==="
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

echo "ISO tree:"
find "$ISO_DIR" -type f -exec du -h {} \;

# ---- Step 4: Create ISO with grub-mkrescue ----
echo ""
echo "=== [4/4] Creating ISO with grub-mkrescue ==="
ISO_FILE="$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso"

grub-mkrescue -o "$ISO_FILE" "$ISO_DIR" || {
    echo "ERROR: grub-mkrescue failed" >&2
    exit 1
}

# ---- Verify ----
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
sha256sum "$(basename "$ISO_FILE")" > "$(basename "$ISO_FILE").sha256"

echo ""
echo "========================================="
echo "  BUILD SUCCESSFUL"
echo "========================================="
echo "ISO:    $ISO_FILE"
echo "Size:   $(du -h "$ISO_FILE" | cut -f1)"
echo "SHA256: $(cat "$ISO_FILE.sha256")"
echo "========================================="
