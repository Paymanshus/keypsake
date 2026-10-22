#!/bin/bash
# One-time: creates a private keychain holding a self-signed "keypsake-local" code-signing identity.
# build.sh unlocks it with a generated password, so builds never prompt for your login password.
# Local development only. Shipping to other people needs an Apple Developer ID (see README).
set -euo pipefail
cd "$(dirname "$0")/.."
KC="$HOME/Library/Keychains/keypsake-dev.keychain-db"
PWFILE=".signing-password"

if [[ -f "$KC" ]]; then echo "already set up: $KC"; exit 0; fi
[[ -f "$PWFILE" ]] || openssl rand -hex 24 > "$PWFILE"
chmod 600 "$PWFILE"
PW=$(cat "$PWFILE")

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cs.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = keypsake-local
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/k.pem" -out "$TMP/c.pem" -days 3650 -config "$TMP/cs.cnf" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/k.pem" -in "$TMP/c.pem" -out "$TMP/id.p12" -passout pass:"$PW"

security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"            # no auto-lock
security unlock-keychain -p "$PW" "$KC"
security import "$TMP/id.p12" -k "$KC" -P "$PW" -T /usr/bin/codesign >/dev/null
# Pre-authorize codesign for this key: this is what removes the password prompt on every build.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
# codesign only finds identities in keychains on the search list.
security list-keychains -d user -s $(security list-keychains -d user | tr -d '"' | xargs) "$KC"
echo "signing identity ready in $KC"
