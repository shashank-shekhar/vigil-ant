#!/bin/bash
# Generate Sparkle EdDSA signing keys for auto-updates.
#
# Run once. Store the private key securely (CI secret: SPARKLE_PRIVATE_KEY).
# Put the public key in Secrets.xcconfig as SPARKLE_PUBLIC_KEY.
#
# Requires: Sparkle checked out via SPM (Xcode resolves packages on first build).

set -euo pipefail

DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData"
GENERATE_KEYS=$(find "$DERIVED_DATA" -path "*/Sparkle/bin/generate_keys" -type f 2>/dev/null | head -1)

if [ -z "$GENERATE_KEYS" ]; then
    echo "Error: generate_keys not found. Build the app in Xcode first so Sparkle gets resolved."
    echo "Then re-run this script."
    exit 1
fi

echo "Generating Sparkle EdDSA signing keys..."
echo ""
"$GENERATE_KEYS"
echo ""
echo "Done. Copy the public key into Secrets.xcconfig as SPARKLE_PUBLIC_KEY."
echo "Save the private key as a GitHub Actions secret named SPARKLE_PRIVATE_KEY."
