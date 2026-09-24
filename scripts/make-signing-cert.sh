#!/bin/zsh
# Creates a self-signed code-signing certificate for Forelight, imports it into
# your login keychain, and writes a .p12 you can add to GitHub secrets.
#
# Signing every release with the same certificate keeps the Accessibility grant
# across updates. TCC stores a requirement like
#
#     identifier "com.forelight.app" and certificate leaf = H"<cert>"
#
# which is stable for one certificate, instead of the `cdhash` an ad-hoc
# signature produces. The certificate does not need to be installed on users'
# Macs; it only has to exist where you sign. Keep the exported .p12: it is the
# identity for every future release, on this Mac and in CI.
#
# Usage:
#   ./scripts/make-signing-cert.sh [name]      # default name: Forelight
#
# Environment:
#   FORELIGHT_P12_PASSWORD   password for the exported .p12 (default: random)
set -euo pipefail

NAME="${1:-Forelight}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
EXPORT_DIR="$ROOT_DIR/dist/signing"
EXPORT_P12="$EXPORT_DIR/$NAME.p12"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "A certificate named \"$NAME\" already exists in your keychains." >&2
    echo "Reusing it keeps the Accessibility grant; use a different name to make" >&2
    echo "a new one, or delete the old one first if it is really unused." >&2
    exit 1
fi

P12_PASSWORD="${FORELIGHT_P12_PASSWORD:-$(openssl rand -hex 16)}"

echo "Creating a self-signed code-signing certificate: $NAME"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK_DIR/key.pem" \
    -out "$WORK_DIR/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning"

openssl pkcs12 -export \
    -inkey "$WORK_DIR/key.pem" \
    -in "$WORK_DIR/cert.pem" \
    -name "$NAME" \
    -out "$WORK_DIR/$NAME.p12" \
    -passout "pass:$P12_PASSWORD"

echo "Importing into the login keychain…"
security import "$WORK_DIR/$NAME.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign

echo "Trusting it for code signing (macOS may ask for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/cert.pem"

mkdir -p "$EXPORT_DIR"
cp "$WORK_DIR/$NAME.p12" "$EXPORT_P12"

echo
echo "Done."
echo
echo "Verify with:"
echo "  security find-identity -p codesigning | grep \"$NAME\""
echo
echo "Sign local releases with:"
echo "  FORELIGHT_SIGNING_IDENTITY=\"$NAME\" ./scripts/release.sh"
echo
echo "For GitHub Actions secrets:"
echo "  MACOS_SIGNING_IDENTITY   = $NAME"
echo "  MACOS_SIGNING_P12        = $(echo "base64 -i \"$EXPORT_P12\" | pbcopy")"
echo "  MACOS_SIGNING_P12_PASSWORD = $P12_PASSWORD"
echo "  MACOS_KEYCHAIN_PASSWORD  = any throwaway password (e.g. \`openssl rand -hex 16\`)"
echo
echo "The .p12 is at $EXPORT_P12 (git-ignored). Back it up somewhere safe:"
echo "losing it means the next release has a new identity and users must grant"
echo "Accessibility again."
