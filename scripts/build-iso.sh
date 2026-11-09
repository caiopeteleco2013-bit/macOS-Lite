#!/bin/bash
#
# build-iso.sh — Build a reproducible macOS-Lite ISO.
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
BUILD_LOG="$OUTPUT_DIR/build.log"

# ---- Reproducibility ----
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"
export SOURCE_DATE_EPOCH
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

echo "========================================="
echo "  macOS-Lite ISO Build"
echo "========================================="
echo "Root:        $ROOT_DIR"
echo "Variant:     $VARIANT"
echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
echo "DATE:        $(date -u)"
echo "========================================="

# ---- Clean previous build artifacts ----
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

exec > >(tee -a "$BUILD_LOG") 2>&1

# ---- Prerequisite check ----
echo ""
echo "=== [1/8] Prerequisite check ==="
for cmd in curl dpkg xorriso grub-mkrescue mksquashfs mtools wget gpg debootstrap; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  OK: $cmd -> $(command -v "$cmd")"
    else
        echo "  MISSING: $cmd" >&2
        exit 1
    fi
done

# ---- Select archives ----
echo ""
echo "=== [2/8] Select archives ==="
case "$VARIANT" in
    default)
        echo "Building DFSG-free variant."
        ARCHIVE_URL="http://deb.debian.org/debian"
        ;;
    nonfree-firmware)
        echo "Building nonfree-firmware variant."
        ARCHIVE_URL="http://deb.debian.org/debian"
        ;;
    *)
        echo "ERROR: unknown variant '$VARIANT'" >&2
        exit 1
        ;;
esac

# ---- Stage shell source into chroot ----
echo ""
echo "=== [3/8] Stage shell source ==="
STAGE_DIR="$CONFIG_DIR/includes.chroot/opt/macos-lite/src"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
if [ -d "$ROOT_DIR/src" ]; then
    cp -a "$ROOT_DIR/src/." "$STAGE_DIR/"
    echo "Staged shell source from $ROOT_DIR/src"
else
    echo "WARNING: No src/ directory found"
fi

# ---- Create chroot with debootstrap ----
echo ""
echo "=== [4/8] Create Debian chroot ==="
CHROOT_DIR="/tmp/macos-lite-chroot"
rm -rf "$CHROOT_DIR"
mkdir -p "$CHROOT_DIR"

echo "Running debootstrap --variant=minimal --arch=amd64 bookworm..."
debootstrap --no-verify-gpg \
    --variant=minimal \
    --arch=amd64 \
    bookworm "$CHROOT_DIR" \
    "${ARCHIVE_URL}/" || {
    echo "ERROR: debootstrap failed" >&2
    exit 1
}

# Verify chroot base system
if [ ! -f "$CHROOT_DIR/bin/bash" ]; then
    echo "ERROR: Chroot missing /bin/bash" >&2
    exit 1
fi
echo "Chroot base system OK"

# ---- Copy includes.chroot ----
echo ""
echo "=== [5/8] Copy custom files into chroot ==="
cp -a "$CONFIG_DIR/includes.chroot/." "$CHROOT_DIR/"
echo "Copied includes.chroot"

# ---- Download and install kernel + essential packages ----
echo ""
echo "=== [6/8] Download and install packages ==="
PKG_DIR="/tmp/macos-lite-pkgs"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"

# Kernel is critical - must be installed
echo "Resolving linux-image-amd64..."
KERNEL_DEB=$(curl -fsSL --max-time 30 \
    "http://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages" 2>/dev/null \
    | awk -v RS='' '/^Package: linux-image-amd64$/{match($0,/Filename: ([^\n]+)/,a); print a[1]; exit}')

if [ -z "$KERNEL_DEB" ]; then
    echo "ERROR: Could not find linux-image-amd64 in archive" >&2
    exit 1
fi
echo "Found: $KERNEL_DEB"

curl -fsSL --max-time 120 \
    -o "$PKG_DIR/linux-image-amd64.deb" \
    "http://deb.debian.org/debian/${KERNEL_DEB}" || {
    echo "ERROR: Failed to download linux-image-amd64" >&2
    exit 1
}
echo "Downloaded linux-image-amd64"

# Also get linux-base (dependency)
echo "Resolving linux-base..."
LINUX_BASE_DEB=$(curl -fsSL --max-time 30 \
    "http://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages" 2>/dev/null \
    | awk -v RS='' '/^Package: linux-base$/{match($0,/Filename: ([^\n]+)/,a); print a[1]; exit}')

if [ -n "$LINUX_BASE_DEB" ]; then
    curl -fsSL --max-time 60 \
        -o "$PKG_DIR/linux-base.deb" \
        "http://deb.debian.org/debian/${LINUX_BASE_DEB}" || {
        echo "WARNING: Failed to download linux-base (non-critical)"
    }
    echo "Downloaded linux-base"
fi

# Install into chroot
echo "Installing kernel into chroot..."
dpkg --root="$CHROOT_DIR" -i "$PKG_DIR/linux-image-amd64.deb" 2>&1 || {
    echo "dpkg --root failed, trying manual extraction..."
    dpkg-deb -x "$PKG_DIR/linux-image-amd64.deb" "$CHROOT_DIR/" 2>/dev/null || true
}

# Verify kernel
KERNEL_COUNT=$(ls "$CHROOT_DIR/boot/vmlinuz-*amd64" 2>/dev/null | wc -l)
if [ "$KERNEL_COUNT" -eq 0 ]; then
    echo "ERROR: No kernel found in chroot after installation" >&2
    echo "Contents of /boot in chroot:" >&2
    ls -la "$CHROOT_DIR/boot/" 2>/dev/null || echo "  (no /boot directory)" >&2
    exit 1
fi
echo "Kernel installed: $KERNEL_COUNT file(s)"

# Install other essential packages
echo ""
echo "Installing other essential packages..."
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
        echo "Installing $(basename "$DEB_FILE")..."
        dpkg --root="$CHROOT_DIR" -i "$DEB_FILE" 2>/dev/null || {
            dpkg-deb -x "$DEB_FILE" "$CHROOT_DIR/" 2>/dev/null || true
        }
    fi
done

# ---- Run chroot hooks ----
echo ""
echo "=== [7/8] Run chroot hooks ==="
for hook in "$CONFIG_DIR"/hooks/*.hook.chroot; do
    [ -f "$hook" ] || continue
    hn=$(basename "$hook")
    echo "Running hook: $hn"
    cp "$hook" "$CHROOT_DIR/tmp/hook_$hn"
    chroot "$CHROOT_DIR" /tmp/hook_$hn 2>/dev/null || {
        echo "  WARNING: Hook $hn failed (non-critical)"
    }
    rm -f "$CHROOT_DIR/tmp/hook_$hn"
done

# ---- Verify kernel and initrd exist ----
echo ""
echo "=== [8/8] Create ISO image ==="
KERNEL=$(ls "$CHROOT_DIR/boot/vmlinuz-*amd64" | head -1)
INITRD=$(ls "$CHROOT_DIR/boot/initrd.img-*amd64" | head -1)
if [ -z "$KERNEL" ] || [ -z "$INITRD" ]; then
    echo "ERROR: No kernel/initrd found in chroot" >&2
    echo "Boot directory contents:" >&2
    ls -la "$CHROOT_DIR/boot/" 2>/dev/null || echo "  (empty)" >&2
    exit 1
fi
echo "Kernel: $(basename "$KERNEL")"
echo "Initrd: $(basename "$INITRD")"

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

# Create the ISO
echo "Creating ISO with xorriso..."
xorriso -as mkisofs \
    -o "$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" \
    -V "macOS-Lite" \
    -volid "macOS-Lite" \
    -A "macOS-Lite" \
    -b boot/grub/i386-pc/eltorito.img \
    -c boot/grub/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    "$ISO_DIR" || {
    echo "ERROR: xorriso failed" >&2
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

# Generate checksums
cd "$OUTPUT_DIR"
sha256sum "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" \
    > "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso.sha256"

echo ""
echo "========================================="
echo "  BUILD SUCCESSFUL"
echo "========================================="
echo "ISO:       $OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso"
echo "SHA256:    $OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso.sha256"
echo "Size:      $(du -h "$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" | cut -f1)"
echo "========================================="
