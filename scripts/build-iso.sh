#!/bin/bash
#
# build-iso.sh — Build a reproducible macOS-Lite ISO.
#
# Tries apt-get with Debian mirror first, falls back to downloading .deb
# packages directly with curl and installing with dpkg.
#
# Usage: ./scripts/build-iso.sh [variant]
#   variant: "" (default, DFSG-free) | "nonfree-firmware"
#
set -uo pipefail

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
for cmd in curl dpkg xorriso grub-mkrescue mksquashfs mtools e2fsprogs wget; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  OK: $cmd"
    else
        echo "  MISSING: $cmd"
    fi
done

# ---- Try to install debootstrap via apt-get with Debian mirror ----
echo "=== Trying apt-get with Debian mirror ==="
echo "deb http://deb.debian.org/debian/ bookworm main contrib non-free-firmware" > /etc/apt/sources.list
if apt-get update 2>&1 | tail -5; then
    echo "apt-get update succeeded"
    if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends debootstrap live-build 2>&1 | tail -5; then
        echo "apt-get install succeeded"
        HAS_DEBOOTSTRAP=1
    else
        echo "apt-get install failed, will download debootstrap directly"
        HAS_DEBOOTSTRAP=0
    fi
else
    echo "apt-get update failed, will download debootstrap directly"
    HAS_DEBOOTSTRAP=0
fi

# ---- Fallback: download debootstrap .deb directly with curl ----
if [ "$HAS_DEBOOTSTRAP" != "1" ]; then
    echo "=== Downloading debootstrap directly ==="
    DEBOOTSTRAP_DEB="/tmp/debootstrap_all.deb"
    if curl -fsSL --max-time 60 \
        -o "$DEBOOTSTRAP_DEB" \
        "http://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_all.deb" 2>/dev/null; then
        echo "Downloaded debootstrap_all.deb"
        dpkg -i "$DEBOOTSTRAP_DEB" 2>/dev/null || true
        dpkg --configure -a 2>/dev/null || true
    else
        # Try specific version
        echo "Trying specific version..."
        for ver in 1.0.131 1.0.130 1.0.129 1.0.128; do
            if curl -fsSL --max-time 30 \
                -o "$DEBOOTSTRAP_DEB" \
                "http://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_${ver}_all.deb" 2>/dev/null; then
                echo "Downloaded debootstrap ${ver}"
                dpkg -i "$DEBOOTSTRAP_DEB" 2>/dev/null || true
                dpkg --configure -a 2>/dev/null || true
                break
            fi
        done
    fi
fi

which debootstrap || {
    echo "ERROR: debootstrap not available after all attempts" >&2
    exit 1
}
echo "debootstrap: $(debootstrap --version)"

# ---- Select archives config ----
case "$VARIANT" in
    default)
        echo "Building DFSG-free variant."
        ARCHIVE_URL="http://deb.debian.org/debian"
        EXTRA_AREAS="main"
        ;;
    nonfree-firmware)
        echo "Building nonfree-firmware variant."
        ARCHIVE_URL="http://deb.debian.org/debian"
        EXTRA_AREAS="main contrib non-free-firmware"
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

# ---- Copy includes.chroot into chroot ----
echo "=== Copying custom files into chroot ==="
cp -a "$CONFIG_DIR/includes.chroot/." "$CHROOT_DIR/"

# ---- Run chroot hooks ----
echo "=== Running chroot hooks ==="
for hook in "$CONFIG_DIR"/hooks/*.hook.chroot; do
    [ -f "$hook" ] || continue
    hook_name=$(basename "$hook")
    echo "Running hook: $hook_name"
    cp "$hook" "$CHROOT_DIR/tmp/hook_$(basename "$hook")"
    chroot "$CHROOT_DIR" /tmp/hook_$(basename "$hook") 2>/dev/null || {
        echo "  WARNING: Hook $hook_name failed (non-critical)"
    }
    rm -f "$CHROOT_DIR/tmp/hook_$(basename "$hook")"
done

# ---- Download and install essential packages into chroot ----
echo "=== Downloading and installing essential packages ==="
PKG_DIR="/tmp/macos-lite-pkgs"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"

ESSENTIAL_PKGS=(
    wayfire
    plank
    dunst
    wofi
    pipewire
    pipewire-pulse
    network-manager
    seatd
    elogind
    brightnessctl
    wlr-randr
)

for pkg in "${ESSENTIAL_PKGS[@]}"; do
    echo "Resolving $pkg..."
    PKG_FILE=$(curl -fsSL --max-time 30 \
        "http://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages" 2>/dev/null \
        | awk -v pkg="$pkg" '
            $1 == "Package:" && $2 == pkg { found=1 }
            found && $1 == "Filename:" { print $2; found=0; exit }
        ')
    if [ -n "$PKG_FILE" ]; then
        DEB_FILE="$PKG_DIR/$(basename "$PKG_FILE")"
        if [ ! -f "$DEB_FILE" ]; then
            curl -fsSL --max-time 60 \
                -o "$DEB_FILE" \
                "http://deb.debian.org/debian/${PKG_FILE}" || {
                echo "  WARNING: Failed to download $pkg"
                continue
            }
        fi
        echo "  OK: $(basename "$PKG_FILE")"
    else
        echo "  WARNING: $pkg not found in archive"
    fi
done

# Install downloaded packages into chroot
for deb in "$PKG_DIR"/*.deb; do
    [ -f "$deb" ] || continue
    echo "Installing $(basename "$deb") into chroot..."
    dpkg --root="$CHROOT_DIR" -i "$deb" 2>/dev/null || {
        dpkg-deb -x "$deb" "$CHROOT_DIR/" 2>/dev/null || true
    }
done

# ---- Create the ISO ----
echo "=== Creating ISO image ==="
ISO_DIR="$OUTPUT_DIR/iso"
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR/boot/grub"

# Copy kernel and initrd from chroot
KERNEL=$(ls "$CHROOT_DIR/boot/vmlinuz-*amd64" 2>/dev/null | head -1)
INITRD=$(ls "$CHROOT_DIR/boot/initrd.img-*amd64" 2>/dev/null | head -1)
if [ -n "$KERNEL" ] && [ -n "$INITRD" ]; then
    cp "$KERNEL" "$ISO_DIR/boot/vmlinuz"
    cp "$INITRD" "$ISO_DIR/boot/initrd.img"
else
    echo "WARNING: No kernel/initrd found in chroot, ISO may not boot"
fi

# Create GRUB config
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

# Create the ISO with xorriso
xorriso -as mkisofs \
    -o "$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" \
    -V "macOS-Lite" \
    -volid "macOS-Lite" \
    -A "macOS-Lite" \
    -b boot/grub/i386-pc/eltorito.img \
    -c boot/grub/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    "$ISO_DIR" 2>/dev/null || {
    echo "ERROR: xorriso failed" >&2
    exit 1
}

# ---- Generate checksums ----
cd "$OUTPUT_DIR"
sha256sum "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" \
    > "macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso.sha256"

echo ""
echo "=== Build complete ==="
echo "ISO:       $OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso"
echo "SHA256:    $OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso.sha256"
echo "Size:      $(du -h "$OUTPUT_DIR/macos-lite-${VARIANT}-amd64-${DATESTAMP}.iso" | cut -f1)"

# ---- Restore archives ----
if [ "$VARIANT" = "nonfree-firmware" ] && [ -f "$CONFIG_DIR/archives/debian.list.chroot.bak" ]; then
    mv "$CONFIG_DIR/archives/debian.list.chroot.bak" "$CONFIG_DIR/archives/debian.list.chroot"
fi
