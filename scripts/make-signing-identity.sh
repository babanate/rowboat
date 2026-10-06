#!/bin/sh
# Creates a self-signed code-signing identity "Rowboat Local Signing" in the
# login keychain, so builds keep a stable signature and macOS keeps the
# Accessibility and Screen Recording grants across updates. Run once.
set -eu
D="$HOME/Library/Application Support/Rowboat/signing"
mkdir -p "$D"; chmod 700 "$D"; cd "$D"
if security find-identity -v -p codesigning | grep -q '"Rowboat Local Signing"'; then echo "identity already present"; exit 0; fi
cat > ext.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Rowboat Local Signing
O = Rowboat
[v3]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -keyout key.pem -out cert.pem -config ext.cnf 2>/dev/null
PASS=$(openssl rand -hex 12)
# Legacy PKCS12 parameters: the keychain rejects OpenSSL 3's default MAC.
openssl pkcs12 -export -legacy -out id.p12 -inkey key.pem -in cert.pem -name "Rowboat Local Signing" -passout "pass:$PASS" 2>/dev/null \
  || openssl pkcs12 -export -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -out id.p12 -inkey key.pem -in cert.pem -name "Rowboat Local Signing" -passout "pass:$PASS"
security import id.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" cert.pem
rm -f key.pem id.p12; chmod 600 cert.pem
security find-identity -v -p codesigning | grep "Rowboat Local Signing"
