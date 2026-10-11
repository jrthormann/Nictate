#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# Creates the self-signed "Nictate Local Signing" identity so rebuilds keep a stable signature (macOS then
# keeps the Screen Recording permission). Run once with `make setup`; running it again does nothing.
#
# macOS ties the Screen Recording grant to "this identifier, signed by this certificate", so whoever can
# sign with the key inherits the grant. The identity is therefore kept out of the login keychain:
# - it lives in its own keychain, ~/Library/Keychains/nictate-signing.keychain-db, with a password you
#   choose here (use one different from your login password; nothing stores it). The keychain locks
#   when the Mac sleeps, so scripts/build-app.sh asks for the password once after each wake, at the first build;
# - the keychain is not added to the search list: only scripts/build-app.sh, which names its path, finds it;
# - the private key is imported non-extractable (-x) and only codesign may use it (-T, partition list);
# - the certificate is not marked as trusted: codesign signs and verifies with an untrusted
#   self-signed certificate, so the Mac gains no new trusted root.
# Residual risk: while the keychain is unlocked, any program running as you can still call codesign
# with this key. Locking it (`security lock-keychain ~/Library/Keychains/nictate-signing.keychain-db`)
# closes that window until the next build.
#
# Moving from the older login-keychain certificate: scripts/build-app.sh prefers this keychain. Development builds still
# fall back to "Nictate Local Signing" in the login keychain, with a warning, so the old one can stay until you remove
# it. make dmg never falls back: the release certificate must be in this keychain and pinned in
# scripts/release-signing.txt. A different certificate asks users for Screen Recording again, so grant it once more
# after the first build with it.
# Then remove the old identity and its trust setting by hand (this script never does):
#   security find-certificate -c "Nictate Local Signing" -Z ~/Library/Keychains/login.keychain-db | grep SHA-1
#   security delete-identity -t -Z <that SHA-1> ~/Library/Keychains/login.keychain-db
set -euo pipefail
source "${0:A:h}/signing_keychain.zsh"
KC=$NICTATE_SIGNING_KEYCHAIN
NAME=$NICTATE_SIGNING_NAME

if signing_keychain_hash >/dev/null; then
    echo "'$NAME' already exists in $KC."; exit 0
fi

# A fresh keychain asks for a new password twice; an existing one (left without the identity) for its own.
password=""
if [[ -f "$KC" ]]; then
    printf 'Password of the existing signing keychain %s: ' "$KC" >&2
    read -rs password; echo >&2
else
    echo "Choose a password for the new signing keychain $KC." >&2
    echo "Use one different from your login password; scripts/build-app.sh asks for it after the Mac wakes." >&2
    while true; do
        printf 'New password: ' >&2; read -rs password; echo >&2
        printf 'Again: ' >&2; read -rs confirm; echo >&2
        if [[ -z "$password" ]]; then echo "The password cannot be empty." >&2
        elif [[ "$password" != "$confirm" ]]; then echo "The passwords differ." >&2
        else break; fi
    done
    unset confirm
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOC
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOC
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# The p12 exists only to carry the key into the keychain; a random password keeps even that copy sealed.
p12pass=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout "pass:$p12pass"
rm -f "$TMP/key.pem"

# Every password goes to `security -i` on standard input, never as an argument. The keychain locks on
# sleep only (no idle timeout). The partition list lets Apple tools such as codesign use the key without
# a GUI prompt; -T limits the key's access list to codesign.
qkc=$(signing_quote "$KC"); qpw=$(signing_quote "$password")
{
    [[ -f "$KC" ]] || print -r -- "create-keychain -p $qpw $qkc"
    print -r -- "unlock-keychain -p $qpw $qkc"
} | signing_security 2>/dev/null
# Importing into a keychain that is still locked would raise a GUI password dialog, so stop here instead.
if ! signing_keychain_status; then
    echo "error: could not unlock $KC (wrong password?)" >&2; exit 1
fi
{
    print -r -- "set-keychain-settings -l $qkc"
    print -r -- "import $(signing_quote "$TMP/id.p12") -k $qkc -P $p12pass -x -T /usr/bin/codesign"
    print -r -- "set-key-partition-list -S apple-tool:,apple: -s -k $qpw $qkc"
} | signing_security
unset password qpw p12pass

hash=$(signing_keychain_hash) || { echo "error: the identity did not reach $KC (wrong password?)" >&2; exit 1; }
# Proves codesign can use the key from this keychain, on a scratch copy of a tiny system binary.
cp /usr/bin/true "$TMP/probe"
codesign --force --keychain "$KC" --sign "$hash" "$TMP/probe" 2>/dev/null \
    || { echo "error: codesign could not sign with '$NAME' from $KC" >&2; exit 1; }
echo "Created '$NAME' in $KC."
echo "Its SHA-1 is $hash. Releases use the certificate pinned in scripts/release-signing.txt: pin this SHA-1 there only on purpose, in a commit."
echo "Now run ./scripts/build-app.sh"
