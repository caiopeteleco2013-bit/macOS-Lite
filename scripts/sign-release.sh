#!/bin/bash
#
# sign-release.sh — GPG-sign a built macOS-Lite ISO and checksums.
#
# Usage: ./scripts/sign-release.sh <iso-path> [key-id]
#
# Signs:
#   <iso>.sha256          (detached signature -> <iso>.sha256.sig)
#   <iso>                 (detached signature -> <iso>.sig)
#
# The GPG private key must be available in the keyring. In CI the key is
# imported from the MACOS_LITE_GPG_PRIVATE_KEY secret (ASCII-armored).
#
set -euo pipefail

ISO="${1:-}"
KEY_ID="${2:-macos-lite-release}"

if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
    echo "Usage: $0 <iso-path> [key-id]" >&2
    exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found. Install gnupg." >&2
    exit 1
fi

SHA="${ISO}.sha256"
if [ ! -f "$SHA" ]; then
    echo "Generating $SHA"
    sha256sum "$ISO" > "$SHA"
fi

echo "Importing/trusting GPG key '$KEY_ID'..."
if ! gpg --list-secret-keys "$KEY_ID" >/dev/null 2>&1; then
    echo "WARNING: secret key '$KEY_ID' not found in keyring."
    echo "Import it first (CI does this from the GPG secret):"
    echo "  gpg --import macos-lite-release.asc"
    exit 1
fi

# Detached signature for the checksums file
echo "Signing $SHA ..."
gpg --default-key "$KEY_ID" --armor --detach-sign "$SHA"

# Detached signature for the ISO itself (convenience)
echo "Signing $ISO ..."
gpg --default-key "$KEY_ID" --armor --detach-sign "$ISO"

echo ""
echo "=== Signing complete ==="
echo "ISO:         $ISO"
echo "SHA256:      $SHA"
echo "SHA256.sig:  $SHA.sig"
echo "ISO.sig:     $ISO.sig"
echo ""
echo "Verify with:"
echo "  gpg --verify $SHA.sig $SHA"
echo "  gpg --verify $ISO.sig $ISO"
