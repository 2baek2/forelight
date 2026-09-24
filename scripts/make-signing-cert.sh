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

P12_PASSWORD="${FORELIGHT_P12_PASSWORD:-}"

print_usage_help() {
    echo
    echo "Sign local releases with:"
    echo "  FORELIGHT_SIGNING_IDENTITY=\"$NAME\" ./scripts/release.sh"
    echo "  (release.sh picks \"$NAME\" automatically when it is installed)"
    echo
    echo "For GitHub Actions secrets:"
    echo "  MACOS_SIGNING_IDENTITY     = $NAME"
    echo "  MACOS_SIGNING_P12          = base64 of the .p12"
    echo "  MACOS_SIGNING_P12_PASSWORD = the .p12 password"
    echo "  MACOS_KEYCHAIN_PASSWORD    = any throwaway password"
    echo
    echo "Keep the .p12 safe. Losing it means the next release has a new identity"
    echo "and users must grant Accessibility again."
}

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "Certificate \"$NAME\" already exists; reusing it."
    security find-certificate -c "$NAME" -p > "$WORK_DIR/cert.pem"

    if ! security verify-cert -c "$WORK_DIR/cert.pem" -p codeSign >/dev/null 2>&1; then
        echo "Trusting it for code signing (macOS may ask for your password)…"
        security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/cert.pem"
    fi

    if [[ -f "$EXPORT_P12" ]]; then
        echo "Reusing exported identity: $EXPORT_P12"
    else
        echo
        echo "It has no exported .p12 yet. Export it once for CI secrets:"
        echo "  키체인 접근 → login → 인증서에서 \"$NAME\" 우클릭 → 내보내기…"
        echo "  (Keychain Access → login → export \"$NAME\" as .p12)"
        echo "  then: mkdir -p \"$(dirname "$EXPORT_P12")\" && mv ~/Desktop/*.p12 \"$EXPORT_P12\""
    fi

    print_usage_help
else
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
    echo "Exported identity: $EXPORT_P12 (git-ignored)"
    print_usage_help
    echo
    echo "The .p12 password is: $P12_PASSWORD"
    exit 0
fi
