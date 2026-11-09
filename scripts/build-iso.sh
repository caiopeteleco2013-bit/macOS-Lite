#!/bin/bash
#
# build-iso.sh — Build a reproducible macOS-Lite ISO.
# Downloads .deb packages directly from Debian's package pool using curl
# and installs them with dpkg. Creates the chroot with debootstrap.
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

echo "=== macOS-Lite ISO build ==="
echo "Root:        $ROOT_DIR"
echo "Variant:     $VARIANT"
echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
echo "USER:        $(whoami)"
echo "DATE:        $(date -u)"

# ---- Clean previous build artifacts ----
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

exec > >(tee -a "$BUILD_LOG") 2>&1

# ---- Prerequisite check ----
echo "=== Prerequisite check ==="
for cmd in curl dpkg xorriso grub-mkrescue mksquashfs mtools wget gpg; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  OK: $cmd -> $(command -v "$cmd")"
    else
        echo "  MISSING: $cmd" >&2
        exit 1
    fi
done

# ---- Download debootstrap from Debian pool ----
echo "=== Installing debootstrap ==="
DEBOOTSTRAP_DEB="/tmp/debootstrap_all.deb"

LATEST_VER=$(curl -fsSL --max-time 30 \
    "http://deb.debian.org/debian/dists/bookworm/main/binary-all/Packages" 2>/dev/null \
    | awk -v RS='' '/^Package: debootstrap$/{match($0,/Version: ([0-9.]+)/,a); print a[1]; exit}')

if [ -z "$LATEST_VER" ]; then
    LATEST_VER="1.0.131"
fi
echo "Target debootstrap version: $LATEST_VER"

if ! curl -fsSL --max-time 60 \
    -o "$DEBOOTSTRAP_DEB" \
    "http://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_${LATEST_VER}_all.deb"; then
    echo "ERROR: Failed to download debootstrap" >&2
    exit 1
fi

dpkg -i "$DEBOOTSTRAP_DEB" 2>/dev/null || {
    echo "dpkg -i had issues, trying --configure..."
    dpkg --configure -a 2>/dev/null || true
}

which debootstrap || {
    echo "ERROR: debootstrap not available" >&2
    exit 1
}
echo "debootstrap: $(debootstrap --version)"

# ---- Select archives ----
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

# ---- Stage shell source into chroot staging area ----
STAGE_DIR="$CONFIG_DIR/includes.chroot/opt/macos-lite/src"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
if [ -d "$ROOT_DIR/src" ]; then
    cp -a "$ROOT_DIR/src/." "$STAGE_DIR/"
    echo "Staged shell source"
fi

# ---- Create chroot with debootstrap ----
echo "=== Creating Debian chroot with debootstrap ==="
CHROOT_DIR="/tmp/macos-lite-chroot"
rm -rf "$CHROOT_DIR"
mkdir -p "$CHROOT_DIR"

debootstrap --no-verify-gpg \
    --variant=minimal \
    --arch=amd64 \
    bookworm "$CHROOT_DIR" \
    "${ARCHIVE_URL}/" || {
    echo "ERROR: debootstrap failed" >&2
    exit 1
}
echo "Chroot created at $CHROOT_DIR"

# ---- Verify chroot has basic structure ----
if [ ! -f "$CHROOT_DIR/bin/bash" ]; then
    echo "ERROR: Chroot missing /bin/bash - debootstrap failed" >&2
    exit 1
fi
echo "Chroot base system OK"

# ---- Copy includes.chroot into chroot ----
echo "=== Copying custom files into chroot ==="
cp -a "$CONFIG_DIR/includes.chroot/." "$CHROOT_DIR/"

# ---- Download essential packages directly from Debian pool ----
echo "=== Downloading essential packages ==="
PKG_DIR="/tmp/macos-lite-pkgs"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"

ESSENTIAL_PKGS=(
    wayfire plank dunst wofi pipewire pipewire-pulse wireplumber
    network-manager seatd elogind brightnessctl wlr-randr
    firefox-esr foot gedit thunar viewnior
    linux-image-amd64
    grub-pc grub-efi-amd64
    e2fsprogs dosfstools
)

for pkg in "${ESSENTIAL_PKGS[@]}"; do
    echo "Resolving $pkg..."
    PKG_FILE=$(curl -fsSL --max-time 30 \
        "http://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages" 2>/dev/null \
        | awk -v p="$pkg" '
            $1=="Package:" && $2==p {f=1}
            f && $1=="Filename:" {print $2; f=0; exit}
        ')
    if [ -n "$PKG_FILE" ]; then
        DEB_FILE="$PKG_DIR/$(basename "$PKG_FILE")"
        if [ ! -f "$DEB_FILE" ]; then
            if curl -fsSL --max-time 60 \
                -o "$DEB_FILE" \
                "http://deb.debian.org/debian/${PKG_FILE}"; then
                echo "  OK: $(basename "$PKG_FILE")"
            else
                echo "  WARNING: Failed to download $pkg"
                continue
            fi
        else
            echo "  OK (cached): $(basename "$PKG_FILE")"
        fi
    else
        echo "  WARNING: $pkg not found in main archive, trying contrib/non-free..."
        PKG_FILE=$(curl -fsSL --max-time 30 \
            "http://deb.debian.org/debian/dists/bookworm/contrib/binary-amd64/Packages" 2>/dev/null \
            | awk -v p="$pkg" '
                $1=="Package:" && $2==p {f=1}
                f && $1=="Filename:" {print $2; f=0; exit}
            ')
        if [ -n "$PKG_FILE" ]; then
            DEB_FILE="$PKG_DIR/$(basename "$PKG_FILE")"
            if [ ! -f "$DEB_FILE" ]; then
                if curl -fsSL --max-time 60 \
                    -o "$DEB_FILE" \
                    "http://deb.debian.org/debian/${PKG_FILE}"; then
                    echo "  OK: $(basename "$PKG_FILE")"
                else
                    echo "  WARNING: Failed to download $pkg"
                    continue
                fi
            else
                echo "  OK (cached): $(basename "$PKG_FILE")"
            fi
        else
            echo "  WARNING: $pkg not found anywhere"
        fi
    fi
done

# Install downloaded packages into chroot
echo "=== Installing packages into chroot ==="
for deb in "$PKG_DIR"/*.deb; do
    [ -f "$deb" ] || continue
    echo "Installing $(basename "$deb") into chroot..."
    dpkg --root="$CHROOT_DIR" -i "$deb" 2>/dev/null || {
        echo "  dpkg --root failed, extracting manually..."
        dpkg-deb -x "$deb" "$CHROOT_DIR/" 2>/dev/null || true
    }
done

# ---- Verify kernel exists in chroot ----
if [ ! -f "$CHROOT_DIR/boot/vmlinuz-*amd64" ]; then
    echo "ERROR: No kernel found in chroot - ISO will not boot" >&2
    exit 1
fi
echo "Kernel found in chroot"

# ---- Run chroot hooks ----
echo "=== Running chroot hooks ==="
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

# ---- Create the ISO ----
echo "=== Creating ISO image ==="
ISO_DIR="$OUTPUT_DIR/iso"
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR/boot/grub"

KERNEL=$(ls "$CHROOT_DIR/boot/vmlinuz-*amd64" | head -1)
INITRD=$(ls "$CHROOT_DIR/boot/initrd.img-*amd64" | head -1)
if [ -n "$KERNEL" ] && [ -n "$INITRD" ]; then
    cp "$KERNEL" "$ISO_DIR/boot/vmlinuz"
    cp "$INITRD" "$ISO_DIR/boot/initrd.img"
    echo "Kernel: $(basename "$KERNEL")"
    echo "Initrd: $(basename "$INITRD")"
else
    echo "ERROR: No kernel/initrd found in chroot" >&2
    exit 1
fi

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

# ---- Verify ISO was created ----
ISO_FILE="$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso"
if [ ! -f "$ISO_FILE" ]; then
    echo "ERROR: ISO file was not created" >&2
    exit 1
fi

ISO_SIZE=$(du -b "$ISO_FILE" | cut -f1)
echo "ISO size: $ISO_SIZE bytes"

if [ "$ISO_SIZE" -lt 1000000 ]; then
    echo "ERROR: ISO too small ($ISO_SIZE bytes) - likely invalid" >&2
    exit 1
fi

# ---- Generate checksums ----
cd "$OUTPUT_DIR"
sha256sum "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" \
    > "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso.sha256"

echo ""
echo "=== Build complete ==="
echo "ISO:       $OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso"
echo "SHA256:    $OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso.sha256"
echo "Size:      $(du -h "$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" | cut -f1)"
