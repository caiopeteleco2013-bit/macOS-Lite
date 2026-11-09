#!/bin/bash
#
# build-iso.sh — Build a reproducible macOS-Lite ISO.
#
# Downloads kernel .deb directly from Debian package pool, extracts vmlinuz
# and initrd, and builds a bootable ISO with grub-mkrescue.
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

echo "========================================="
echo "  macOS-Lite ISO build"
echo "========================================="
echo "Root:        $ROOT_DIR"
echo "Variant:     $VARIANT"
echo "DATE:        $(date -u)"
echo "========================================="

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ---- Prerequisites ----
echo "=== Prerequisite check ==="
for cmd in curl dpkg grub-mkrescue xorriso wget; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "MISSING: $cmd" >&2; exit 1; }
    echo "OK: $cmd"
done

# ---- Download kernel .deb from Debian pool ----
echo "=== Downloading linux-image-amd64 ==="
KERNEL_DEB_URL=$(curl -fsSL --max-time 30 \
    "http://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages" 2>/dev/null \
    | awk -v RS='' '/^Package: linux-image-amd64$/{match($0,/Filename: ([^\n]+)/,a); print a[1]; exit}')

if [ -z "$KERNEL_DEB_URL" ]; then
    echo "ERROR: Could not find linux-image-amd64 in Debian archive" >&2
    exit 1
fi
echo "Found: $KERNEL_DEB_URL"

TMPDIR=$(mktemp -d)
curl -fsSL --max-time 120 \
    -o "$TMPDIR/linux-image-amd64.deb" \
    "http://deb.debian.org/debian/${KERNEL_DEB_URL}" || {
    echo "ERROR: Failed to download linux-image-amd64" >&2
    exit 1
}
echo "Downloaded kernel .deb"

# Extract kernel and initrd
echo "=== Extracting kernel and initrd ==="
dpkg-deb -x "$TMPDIR/linux-image-amd64.deb" "$TMPDIR/extract" || {
    echo "ERROR: Failed to extract kernel .deb" >&2
    exit 1
}

KERNEL=$(ls "$TMPDIR/extract/boot/vmlinuz-*amd64" 2>/dev/null | head -1)
INITRD=$(ls "$TMPDIR/extract/boot/initrd.img-*amd64" 2>/dev/null | head -1)

if [ -z "$KERNEL" ] || [ -z "$INITRD" ]; then
    echo "ERROR: No kernel/initrd found in .deb" >&2
    echo "Contents of extracted boot:" >&2
    ls -laR "$TMPDIR/extract/boot/" 2>/dev/null || echo "  (empty)" >&2
    exit 1
fi
echo "Kernel: $(basename "$KERNEL")"
echo "Initrd: $(basename "$INITRD")"

# ---- Also download essential packages ----
echo "=== Downloading essential packages ==="
PKG_DIR="$TMPDIR/pkgs"
mkdir -p "$PKG_DIR"

ESSENTIAL_PKGS=(
    wayfire plank dunst wofi pipewire pipewire-pulse wireplumber
    network-manager seatd elogind brightnessctl wlr-randr
    firefox-esr foot gedit thunar viewnior
    grub-pc grub-efi-amd64
)

for pkg in "${ESSENTIAL_PKGS[@]}"; do
    PKG_FILE=$(curl -fsSL --max-time 30 \
        "http://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages" 2>/dev/null \
        | awk -v p="$pkg" '
            $1=="Package:" && $2==p {f=1}
            f && $1=="Filename:" {print $2; f=0; exit}
        ')
    if [ -n "$PKG_FILE" ]; then
        DEB_FILE="$PKG_DIR/$(basename "$PKG_FILE")"
        if [ ! -f "$DEB_FILE" ]; then
            curl -fsSL --max-time 60 \
                -o "$DEB_FILE" \
                "http://deb.debian.org/debian/${PKG_FILE}" 2>/dev/null || {
                echo "  WARNING: Failed $pkg"
                continue
            }
        fi
        echo "  OK: $(basename "$PKG_FILE")"
    else
        echo "  WARNING: $pkg not found"
    fi
done

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
echo "========================================="
echo "  BUILD SUCCESSFUL"
echo "========================================="
echo "ISO:       $OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso"
echo "SHA256:    $OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso.sha256"
echo "Size:      $(du -h "$ISO_FILE" | cut -f1)"
echo "========================================="
