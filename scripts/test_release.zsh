#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# Regression tests for release packaging: the approved build numbers, the release signing certificate, and the refusals
# that stop a release from falling back to another certificate. Most cases use stand-in security and codesign tools
# that answer from variables, so no keychain is read. The keychain cases create a throwaway keychain and certificate in
# a temporary folder, sign a throwaway app with them, and remove everything. No password is printed.
set -euo pipefail
cd "$(dirname "$0")/.."

ORIG_PATH="$PATH"
TMP="$(mktemp -d)"
# The user's keychain search list as it was before a case changed it, and whether a case has changed it since.
SEARCH_SAVED=()
SEARCH_CHANGED=""
# Puts back the search list that search_list_open saved. Does nothing when the list is not changed.
restore_search_list() {
    [[ -n "$SEARCH_CHANGED" ]] || return 0
    if ! security list-keychains -d user -s "${SEARCH_SAVED[@]}"; then
        print -r -- "error: could not restore the user's keychain search list" >&2
        return 1
    fi
    SEARCH_CHANGED=""
}
# Restores the search list, deletes the throwaway keychain with its throwaway identity, and removes the folder. Runs on
# every exit: a normal end, a failed assertion, and an interruption (INT, TERM and HUP exit through this trap).
cleanup() {
    local kc="$TMP/e2e/signing.keychain-db"
    restore_search_list || true
    [[ ! -f "$kc" ]] || security delete-keychain "$kc" >/dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
source scripts/signing_keychain.zsh
source scripts/release_signing.zsh
NICTATE_SIGN_FLAGS=(--force --options runtime)

# Cases run in subshells, so each result is also appended to a file the summary counts.
RESULTS="$TMP/results.txt"
: > "$RESULTS"
pass() { print -r -- "PASS  $1"; print -r -- "PASS" >> "$RESULTS"; }
failure() {
    print -r -- "FAIL  $1"
    [[ -z "${2:-}" ]] || print -r -- "$2" | sed 's/^/      /'
    print -r -- "FAIL" >> "$RESULTS"
}
skip() { print -r -- "SKIP  $1"; print -r -- "SKIP" >> "$RESULTS"; }

# fixture_failed STAGE LOG SECRET...: records a failed setup stage. LOG holds what the tool printed; each SECRET is
# removed from it before it is shown.
fixture_failed() {
    local stage="$1" log="$2" detail="" secret
    shift 2
    detail="$(cat "$log" 2>/dev/null || true)"
    for secret in "$@"; do detail="${detail//$secret/[removed]}"; done
    failure "throwaway keychain fixture: $stage" "${detail:-the tool printed nothing}"
}

# expect DESCRIPTION ok|refused NEEDLE COMMAND...: runs COMMAND and checks its exit status, and that its output contains
# NEEDLE when NEEDLE is not empty.
expect() {
    local desc="$1" want="$2" needle="$3" out="" rc=0
    shift 3
    # Stdin is /dev/null, so no case can wait for a password, even when the suite runs from a terminal.
    out="$("$@" 2>&1 </dev/null)" || rc=$?
    if [[ "$want" == ok ]] && (( rc != 0 )); then
        failure "$desc" "expected success, exit $rc: $out"
    elif [[ "$want" == refused ]] && (( rc == 0 )); then
        failure "$desc" "expected a refusal, but it succeeded: $out"
    elif [[ -n "$needle" && "$out" != *"$needle"* ]]; then
        failure "$desc" "the output lacks '$needle': $out"
    else
        pass "$desc"
    fi
}

# Stand-in tools. security answers the release signing queries from FAKE_* variables; codesign logs its calls and signs
# nothing. Each case puts them first on PATH inside its own subshell.
FAKE_BIN="$TMP/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/security" <<'EOF'
#!/bin/sh
# Stand-in for security, for the release signing queries only. No keychain is read.
case "$1" in
    find-certificate)
        for sha in ${FAKE_KC_SHA1S:-}; do
            printf 'SHA-1 hash: %s\n' "$sha"
        done
        ;;
    find-identity)
        [ -z "${FAKE_LOGIN_IDENTITY:-}" ] || printf '  1) 30FAF2A15B50BFBE015BC2F67A48A32C2731B225 "Nictate Local Signing"\n'
        ;;
    *)
        echo "stand-in security: unexpected call: $*" >&2
        exit 2
        ;;
esac
EOF
cat > "$FAKE_BIN/codesign" <<'EOF'
#!/bin/sh
# Stand-in for codesign: logs each call and signs nothing.
echo "codesign $*" >> "$FAKE_LOG"
exit 0
EOF
chmod +x "$FAKE_BIN/security" "$FAKE_BIN/codesign"

use_fakes() {
    export PATH="$FAKE_BIN:$ORIG_PATH" FAKE_LOG="$1"
    : > "$FAKE_LOG"
}

# never_signed LOG DESCRIPTION: passes when codesign was never asked to sign.
never_signed() {
    if grep -q -F -- ' --sign' "$1"; then
        failure "$2" "codesign was called: $(tr '\n' ';' < "$1")"
    else
        pass "$2"
    fi
}

# signed_with LOG PATTERN DESCRIPTION: passes when codesign was asked to sign with PATTERN.
signed_with() {
    if grep -q -F -- "$2" "$1"; then
        pass "$3"
    else
        failure "$3" "no codesign call with '$2': $(tr '\n' ';' < "$1")"
    fi
}

SHA_PINNED=0123456789ABCDEF0123456789ABCDEF01234567
SHA_OTHER=FEDCBA9876543210FEDCBA9876543210FEDCBA98
FAKE_DIR="$TMP/fake"
mkdir -p "$FAKE_DIR"
PIN_PINNED="$FAKE_DIR/pin-pinned.txt"
print -r -- "SHA-1 $SHA_PINNED" > "$PIN_PINNED"
PIN_BAD="$FAKE_DIR/pin-bad.txt"
print -r -- "SHA-1 not-a-hash" > "$PIN_BAD"
APP="$FAKE_DIR/Nictate.app"
mkdir -p "$APP"
KC_PRESENT="$FAKE_DIR/present.keychain-db"
: > "$KC_PRESENT"   # present, but not a keychain: it cannot be unlocked
KC_ABSENT="$FAKE_DIR/absent.keychain-db"

# Release signing refusals, with a same-named certificate in the login keychain in every case.
release_refusals() {
    local log="$FAKE_DIR/release.log"
    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY=1 FAKE_KC_SHA1S=""
        NICTATE_SIGNING_KEYCHAIN="$KC_ABSENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
        expect "release refuses a missing dedicated keychain, though a same-named certificate is in the login keychain" \
            refused "does not exist" sign_for_release "$APP"
    )
    never_signed "$log" "release signs nothing when the dedicated keychain is missing"

    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY=1 FAKE_KC_SHA1S=""
        NICTATE_SIGNING_KEYCHAIN="$KC_PRESENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
        expect "release refuses when the keychain holds no certificate with the release name" \
            refused "has no certificate named" sign_for_release "$APP"
    )
    never_signed "$log" "release signs nothing when the keychain has no release certificate"

    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY=1 FAKE_KC_SHA1S="$SHA_PINNED $SHA_OTHER"
        NICTATE_SIGNING_KEYCHAIN="$KC_PRESENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
        expect "release refuses an ambiguous keychain that holds two certificates with the release name" \
            refused "more than one certificate" sign_for_release "$APP"
    )
    never_signed "$log" "release signs nothing when the release name is ambiguous"

    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY=1 FAKE_KC_SHA1S="$SHA_OTHER"
        NICTATE_SIGNING_KEYCHAIN="$KC_PRESENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
        expect "release refuses a certificate that is not the pinned one" refused "pins" sign_for_release "$APP"
    )
    never_signed "$log" "release signs nothing when the certificate is not the pinned one"

    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY=1 FAKE_KC_SHA1S="$SHA_PINNED"
        NICTATE_SIGNING_KEYCHAIN="$KC_PRESENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
        expect "release refuses a locked keychain instead of falling back to the login-keychain certificate" \
            refused "locked and was not unlocked" sign_for_release "$APP"
    )
    never_signed "$log" "release never falls back to the login-keychain certificate"

    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY=1 FAKE_KC_SHA1S="$SHA_PINNED"
        NICTATE_SIGNING_KEYCHAIN="$KC_PRESENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_BAD"
        expect "release refuses a pin file that does not hold a SHA-1" refused "must hold one line" sign_for_release "$APP"
    )
    never_signed "$log" "release signs nothing with a malformed pin"

    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY=1 FAKE_KC_SHA1S="$SHA_PINNED" SIGN_IDENTITY="Nictate Local Signing"
        NICTATE_SIGNING_KEYCHAIN="$KC_PRESENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
        expect "release refuses SIGN_IDENTITY, which would bypass the pin" refused "not used for releases" sign_for_release "$APP"
    )
    never_signed "$log" "release signs nothing when SIGN_IDENTITY is set"
}

# Development and QA builds keep their fallbacks, and each one says which identity it used.
development_fallbacks() {
    local log="$FAKE_DIR/dev.log"
    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY=1 FAKE_KC_SHA1S=""
        NICTATE_SIGNING_KEYCHAIN="$KC_ABSENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
        expect "development build falls back to the login-keychain certificate, with a warning" \
            ok "login-keychain certificate" sign_for_development "$APP"
    )
    signed_with "$log" "--sign Nictate Local Signing" "development build signs with the login-keychain certificate by name"

    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY="" FAKE_KC_SHA1S=""
        NICTATE_SIGNING_KEYCHAIN="$KC_ABSENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
        expect "development build with no identity signs ad hoc, with a warning" ok "signing ad-hoc" sign_for_development "$APP"
    )
    signed_with "$log" "--sign - " "development build with no identity signs ad hoc"

    (
        use_fakes "$log"
        export FAKE_LOGIN_IDENTITY=1 FAKE_KC_SHA1S="$SHA_PINNED"
        NICTATE_SIGNING_KEYCHAIN="$KC_PRESENT" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
        expect "development build with a locked dedicated keychain warns, then uses the login-keychain certificate" \
            ok "could not sign from" sign_for_development "$APP"
    )
    signed_with "$log" "--sign Nictate Local Signing" "development build keeps its fallback when the dedicated keychain is locked"
}

# Build numbers: beta.2 is approved as 22, so 21 (beta.1) and 1 are refused, as are invalid values.
build_numbers() {
    local ok="$FAKE_DIR/ok-builds.txt" reg="$FAKE_DIR/regress-builds.txt" dup="$FAKE_DIR/dup-builds.txt"
    local bad="$FAKE_DIR/bad-builds.txt" extra="$FAKE_DIR/extra-builds.txt" real=scripts/release-builds.txt
    printf '1.0.0-beta.1 21\n1.0.0-beta.2 22\n1.0.0-beta.3 23\n' > "$ok"
    printf '1.0.0-beta.1 21\n1.0.0-beta.2 22\n1.0.0-beta.3 21\n' > "$reg"
    printf '1.0.0-beta.2 22\n1.0.0-beta.2 22\n' > "$dup"
    printf '1.0.0-beta.2 twenty\n' > "$bad"
    printf '1.0.0-beta.2 22 x\n' > "$extra"
    expect "BUILD_NUMBER=22 is accepted for 1.0.0-beta.2" ok "build 22 for 1.0.0-beta.2 is approved" release_check_build_number 1.0.0-beta.2 22 "$real"
    expect "BUILD_NUMBER=21 is refused for 1.0.0-beta.2 (beta.1's build)" refused "approved for build 22" release_check_build_number 1.0.0-beta.2 21 "$real"
    expect "BUILD_NUMBER=1 is refused for 1.0.0-beta.2" refused "approved for build 22" release_check_build_number 1.0.0-beta.2 1 "$real"
    expect "BUILD_NUMBER=23 is refused for 1.0.0-beta.2, which is approved only as 22" refused "approved for build 22" release_check_build_number 1.0.0-beta.2 23 "$real"
    expect "BUILD_NUMBER=0 is refused" refused "whole number" release_check_build_number 1.0.0-beta.2 0 "$real"
    expect "BUILD_NUMBER=022 is refused (leading zero)" refused "whole number" release_check_build_number 1.0.0-beta.2 022 "$real"
    expect "an empty BUILD_NUMBER is refused" refused "whole number" release_check_build_number 1.0.0-beta.2 "" "$real"
    expect "BUILD_NUMBER=abc is refused" refused "whole number" release_check_build_number 1.0.0-beta.2 abc "$real"
    expect "BUILD_NUMBER=-5 is refused" refused "whole number" release_check_build_number 1.0.0-beta.2 -5 "$real"
    expect "BUILD_NUMBER with a trailing space is refused" refused "whole number" release_check_build_number 1.0.0-beta.2 "22 " "$real"
    expect "a version missing from the list is refused" refused "is not in" release_check_build_number 1.0.0-beta.4 22 "$real"
    expect "a later release is accepted above the builds listed before it" ok "build 23 for 1.0.0-beta.3 is approved" release_check_build_number 1.0.0-beta.3 23 "$ok"
    expect "a later release that repeats an earlier build is refused" refused "approved for build 23" release_check_build_number 1.0.0-beta.3 22 "$ok"
    expect "a later release that regresses below beta.2 is refused" refused "does not exceed build 22" release_check_build_number 1.0.0-beta.3 21 "$reg"
    expect "a version listed twice is refused" refused "more than once" release_check_build_number 1.0.0-beta.2 22 "$dup"
    expect "a non-numeric build in the list is refused" refused "not a whole number" release_check_build_number 1.0.0-beta.2 22 "$bad"
    expect "a list line with extra fields is refused" refused "must be followed by one build number" release_check_build_number 1.0.0-beta.2 22 "$extra"
    expect "a missing list is refused" refused "is missing" release_check_build_number 1.0.0-beta.2 22 "$FAKE_DIR/none.txt"
}

# The committed pin is one valid SHA-1.
pin_file() {
    (
        RELEASE_SIGNING_PIN_FILE="scripts/release-signing.txt"
        expect "the committed release pin is one valid SHA-1" ok "30FAF2A15B50BFBE015BC2F67A48A32C2731B225" release_pinned_sha1
    )
}

# A throwaway app signed ad hoc: strict verification passes, but it carries no certificate to pin.
make_app() {
    local app="$1"
    mkdir -p "$app/Contents/MacOS"
    cp /usr/bin/true "$app/Contents/MacOS/Probe"
    cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Probe</string>
    <key>CFBundleIdentifier</key>
    <string>com.jrthormann.nictate.signingtest</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
EOF
    codesign --force --sign - "$app" >/dev/null 2>&1
}

# user_keychains: the user's keychain search list, one path per line, without the quotes security prints around them.
user_keychains() {
    security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/'
}

# search_list_open KEYCHAIN: saves the user's search list, then adds KEYCHAIN to it. The keychain cases call this on a
# hosted runner only (GITHUB_ACTIONS): on the hosted macOS 26 runner, codesign finds the test identity only when its keychain
# is on the search list. A developer's search list is never changed by these cases, and production signing does not do this.
search_list_open() {
    SEARCH_SAVED=(${(f)"$(user_keychains)"})
    security list-keychains -d user -s "$1" "${SEARCH_SAVED[@]}" || return 1
    SEARCH_CHANGED=1
}

# Real codesign, with a throwaway keychain and certificate: releases are signed by the pinned certificate, a locked
# keychain is refused, and a pin the keychain does not hold is refused. Nothing outside $TMP is touched.
# The setup is made the way scripts/create_signing_cert.sh makes the real identity, and each stage is checked, so a
# failure names the operation that failed and shows what the tool printed.
keychain_cases() {
    local kc="$TMP/e2e/signing.keychain-db" pw p12pw sha rc out="$TMP/e2e/stage.log"
    mkdir -p "$TMP/e2e"
    pw="$(/usr/bin/openssl rand -hex 16)"
    p12pw="$(/usr/bin/openssl rand -hex 16)"
    cat > "$TMP/e2e/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Nictate Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    if ! /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 2 -config "$TMP/e2e/cert.cnf" \
            -keyout "$TMP/e2e/key.pem" -out "$TMP/e2e/cert.pem" >"$out" 2>&1; then
        fixture_failed "openssl could not create the test certificate" "$out" "$pw" "$p12pw"
        return 0
    fi
    if ! P12PW="$p12pw" /usr/bin/openssl pkcs12 -export -inkey "$TMP/e2e/key.pem" -in "$TMP/e2e/cert.pem" \
            -out "$TMP/e2e/id.p12" -passout env:P12PW >"$out" 2>&1; then
        fixture_failed "openssl could not pack the test key and certificate into a PKCS#12 file" "$out" "$pw" "$p12pw"
        return 0
    fi
    rm -f "$TMP/e2e/key.pem"
    if ! { print -r -- "create-keychain -p $(signing_quote "$pw") $(signing_quote "$kc")"
           print -r -- "unlock-keychain -p $(signing_quote "$pw") $(signing_quote "$kc")"; } | signing_security 2>"$out"; then
        fixture_failed "security could not create and unlock the throwaway keychain" "$out" "$pw" "$p12pw"
        return 0
    fi
    # Status 0 is unlocked. Anything else is reported with the status and the helper's own output, so a broken
    # /usr/bin/python3 (it stops when the Xcode license is not accepted) is not mistaken for a locked keychain.
    rc=0
    (NICTATE_SIGNING_KEYCHAIN="$kc"; signing_keychain_status) >"$out" 2>&1 || rc=$?
    if (( rc != 0 )); then
        fixture_failed "the throwaway keychain is not unlocked (status check returned $rc)" "$out" "$pw" "$p12pw"
        return 0
    fi
    if ! { print -r -- "import $(signing_quote "$TMP/e2e/id.p12") -k $(signing_quote "$kc") -P $(signing_quote "$p12pw") -x -T /usr/bin/codesign"
           print -r -- "set-key-partition-list -S apple-tool:,apple: -s -k $(signing_quote "$pw") $(signing_quote "$kc")"; } | signing_security 2>"$out"; then
        fixture_failed "security could not import the test certificate and its key" "$out" "$pw" "$p12pw"
        return 0
    fi
    sha="$(security find-certificate -c "Nictate Local Signing" -Z "$kc" 2>/dev/null | awk '/^SHA-1 hash:/ { print $3; exit }')"
    if [[ -z "$sha" ]]; then
        fixture_failed "the test certificate is not in the throwaway keychain after import" "$out" "$pw" "$p12pw"
        return 0
    fi
    if ! security find-identity -p codesigning "$kc" >"$out" 2>&1 || ! grep -q -F "$sha" "$out"; then
        fixture_failed "the test certificate has no private key in the throwaway keychain, so there is no identity to sign with" \
            "$out" "$pw" "$p12pw"
        return 0
    fi
    # On a hosted runner the keychain joins the search list for the signing cases; cleanup restores the list.
    if [[ -n "${GITHUB_ACTIONS:-}" ]] && ! search_list_open "$kc" >"$out" 2>&1; then
        fixture_failed "could not add the throwaway keychain to the user's search list" "$out" "$pw" "$p12pw"
        return 0
    fi
    cp /usr/bin/true "$TMP/e2e/probe"
    if ! codesign --force --keychain "$kc" --sign "$sha" "$TMP/e2e/probe" >"$out" 2>&1; then
        {
            echo "macOS $(sw_vers -productVersion); search list: $(user_keychains | tr '\n' ' ')"
            security find-identity -p codesigning "$kc" 2>&1
        } >>"$out"
        fixture_failed "codesign cannot sign with the imported identity, though the keychain lists it" "$out" "$pw" "$p12pw"
        return 0
    fi
    print -r -- "SHA-1 $sha" > "$TMP/e2e/pin.txt"
    print -r -- "SHA-1 $SHA_OTHER" > "$TMP/e2e/pin-other.txt"
    make_app "$TMP/e2e/one.app"
    make_app "$TMP/e2e/two.app"

    (
        export PATH="$ORIG_PATH"
        NICTATE_SIGNING_KEYCHAIN="$kc" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$TMP/e2e/pin.txt"
        expect "release signs with the pinned certificate from the dedicated keychain, then verifies it" \
            ok "signed with the pinned certificate" sign_for_release "$TMP/e2e/one.app"
    )
    if [[ "$(release_leaf_sha1 "$TMP/e2e/one.app")" == "$sha" ]]; then
        pass "the released app's certificate is the pinned SHA-1"
    else
        failure "the released app's certificate is the pinned SHA-1" "found: $(release_leaf_sha1 "$TMP/e2e/one.app")"
    fi
    (
        export PATH="$ORIG_PATH"
        RELEASE_SIGNING_PIN_FILE="$TMP/e2e/pin-other.txt"
        expect "verification refuses an app signed with a certificate other than the pin" \
            refused "not the pinned certificate" release_verify_app "$TMP/e2e/one.app"
    )

    security lock-keychain "$kc"
    (
        export PATH="$ORIG_PATH"
        NICTATE_SIGNING_KEYCHAIN="$kc" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$TMP/e2e/pin.txt"
        expect "release refuses a locked keychain, though a same-named certificate is in the login keychain" \
            refused "locked and was not unlocked" sign_for_release "$TMP/e2e/two.app"
    )
    if [[ -z "$(release_leaf_sha1 "$TMP/e2e/two.app")" ]]; then
        pass "nothing was signed while the release keychain was locked"
    else
        failure "nothing was signed while the release keychain was locked" "the app carries a certificate"
    fi
    (
        export PATH="$ORIG_PATH"
        NICTATE_SIGNING_KEYCHAIN="$kc" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$TMP/e2e/pin-other.txt"
        expect "release refuses a pin that the keychain does not hold" refused "pins" sign_for_release "$TMP/e2e/two.app"
    )
    (
        export PATH="$ORIG_PATH"
        NICTATE_SIGNING_KEYCHAIN="$TMP/e2e/absent.keychain-db" NICTATE_SIGNING_NAME="Nictate Local Signing" RELEASE_SIGNING_PIN_FILE="$TMP/e2e/pin.txt"
        expect "release refuses when its keychain does not exist" refused "does not exist" sign_for_release "$TMP/e2e/two.app"
    )
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        if restore_search_list && [[ "$(user_keychains)" == "${(F)SEARCH_SAVED}" ]]; then
            pass "the user's keychain search list is back as it was before the signing cases"
        else
            failure "the user's keychain search list is back as it was before the signing cases" \
                "now: $(user_keychains | tr '\n' ' ')"
        fi
    fi
}

# Release folder claims. build-dmg.sh claims its release folder with claim_release_folder. Each case hosts one claim the way the
# build does (the claim, the EXIT cleanup and the signal handlers) in its own zsh. The interruption cases use a stand-in mkdir
# that signals the host at the exact point the window exists: after mkdir has created the folder, before the claim is
# recorded. The stand-in sends the signal itself, so no case depends on timing.
release_folder_claims() {
    local dir="$TMP/claims" claim_bin="$TMP/claim-bin" host="$TMP/claim-host.zsh" st won=0 s
    mkdir -p "$dir" "$claim_bin"
    cat > "$claim_bin/mkdir" <<'EOF'
#!/bin/sh
# Stand-in for mkdir in the claim cases: runs the real mkdir, then sends SIGTERM to the hosting shell before returning.
/bin/mkdir "$@"
status=$?
kill -TERM "$CLAIMER"
exit $status
EOF
    chmod +x "$claim_bin/mkdir"
    cat > "$host" <<'EOF'
#!/bin/zsh
# Hosts one release folder claim the way scripts/build-dmg.sh does. Arguments: REPO_ROOT DIR
set -euo pipefail
source "$1/scripts/release_signing.zsh"
CREATED_RELEASE=""
cleanup() { [[ -z "$CREATED_RELEASE" ]] || rm -rf "$CREATED_RELEASE"; }
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
export CLAIMER=$$
claim_release_folder "$2" || exit 1
CREATED_RELEASE=""
EOF
    # claim_host DIR [STAND_IN_DIR]: returns the host's exit status.
    claim_host() {
        PATH="${2:+$2:}$ORIG_PATH" zsh "$host" "$PWD" "$1"
    }

    st=0; claim_host "$dir/ordinary" || st=$?
    if (( st == 0 )) && [[ -d "$dir/ordinary" ]]; then
        pass "a release folder claim creates the folder, and a finished build keeps it"
    else
        failure "a release folder claim creates the folder, and a finished build keeps it" "status $st"
    fi

    mkdir "$dir/owned" && print -r -- keep > "$dir/owned/theirs"
    st=0; claim_host "$dir/owned" || st=$?
    if (( st == 1 )) && [[ "$(cat "$dir/owned/theirs" 2>/dev/null)" == keep ]]; then
        pass "an existing release folder is refused, and left with its contents"
    else
        failure "an existing release folder is refused, and left with its contents" "status $st"
    fi

    st=0; claim_host "$dir/interrupted" "$claim_bin" || st=$?
    if (( st == 130 )) && [[ ! -e "$dir/interrupted" ]]; then
        pass "a signal between mkdir and the recorded claim removes the folder that claim created"
    else
        failure "a signal between mkdir and the recorded claim removes the folder that claim created" \
            "status $st, folder left behind: $(test -e "$dir/interrupted" && echo yes || echo no)"
    fi

    mkdir "$dir/owned-interrupted" && print -r -- keep > "$dir/owned-interrupted/theirs"
    st=0; claim_host "$dir/owned-interrupted" "$claim_bin" || st=$?
    if (( st == 130 )) && [[ "$(cat "$dir/owned-interrupted/theirs" 2>/dev/null)" == keep ]]; then
        pass "a signal while another process owns the folder leaves that folder alone"
    else
        failure "a signal while another process owns the folder leaves that folder alone" "status $st"
    fi

    ( st=0; claim_host "$dir/race" || st=$?; print -r -- "$st" > "$dir/race.a" ) &
    ( st=0; claim_host "$dir/race" || st=$?; print -r -- "$st" > "$dir/race.b" ) &
    wait
    for s in "$(cat "$dir/race.a")" "$(cat "$dir/race.b")"; do
        [[ "$s" == 0 ]] && won=$((won + 1))
    done
    if (( won == 1 )) && [[ -d "$dir/race" ]]; then
        pass "two claims for one release folder at once: exactly one creates it"
    else
        failure "two claims for one release folder at once: exactly one creates it" \
            "claims that created it: $won, folder present: $(test -d "$dir/race" && echo yes || echo no)"
    fi
}

# make dmg refuses before anything is built or written. It packages a commit, so these cases run on a clean clone of HEAD:
# no working-tree state (CI's prebuilt/ folder, or uncommitted edits) can skip them. Each case also points the release
# keychain at a path that does not exist, so a case that got past its refusal still could not sign.
packaging_refusals() {
    local clone="$TMP/clone" none="$TMP/no-release-keychain.keychain-db"
    if ! git clone -q --no-hardlinks . "$clone" 2>"$TMP/clone.log"; then
        failure "a clean clone of HEAD for the make dmg refusals" "$(cat "$TMP/clone.log")"
        return 0
    fi
    (
        cd "$clone"
        export NICTATE_SIGNING_KEYCHAIN="$none" BUILD_NUMBER=21 OUT_DIR="$TMP/dmg-21"
        expect "make dmg refuses BUILD_NUMBER=21, the build beta.1 already published" refused "approved for build 22" zsh scripts/build-dmg.sh
    )
    if [[ -e "$TMP/dmg-21" ]]; then failure "no output folder for BUILD_NUMBER=21" "$TMP/dmg-21 exists"; else pass "no output folder for BUILD_NUMBER=21"; fi
    (
        cd "$clone"
        export NICTATE_SIGNING_KEYCHAIN="$none" BUILD_NUMBER=1 OUT_DIR="$TMP/dmg-1"
        expect "make dmg refuses BUILD_NUMBER=1" refused "approved for build 22" zsh scripts/build-dmg.sh
    )
    if [[ -e "$TMP/dmg-1" ]]; then failure "no output folder for BUILD_NUMBER=1" "$TMP/dmg-1 exists"; else pass "no output folder for BUILD_NUMBER=1"; fi
    (
        cd "$clone"
        unset BUILD_NUMBER
        export NICTATE_SIGNING_KEYCHAIN="$none" OUT_DIR="$TMP/dmg-none"
        expect "make dmg refuses a missing BUILD_NUMBER" refused "set BUILD_NUMBER" zsh scripts/build-dmg.sh
    )
    if [[ -e "$TMP/dmg-none" ]]; then failure "no output folder without BUILD_NUMBER" "$TMP/dmg-none exists"; else pass "no output folder without BUILD_NUMBER"; fi
    (
        cd "$clone"
        print -r -- "an uncommitted change" >> CHANGELOG.md
        export NICTATE_SIGNING_KEYCHAIN="$none" BUILD_NUMBER=22 OUT_DIR="$TMP/dmg-dirty"
        expect "make dmg refuses a working tree with changes, even with the approved build 22" \
            refused "the working tree has changes" zsh scripts/build-dmg.sh
    )
    if [[ -e "$TMP/dmg-dirty" ]]; then failure "no output folder for a dirty working tree" "$TMP/dmg-dirty exists"; else pass "no output folder for a dirty working tree"; fi
}

release_refusals
development_fallbacks
build_numbers
pin_file
make_app "$TMP/adhoc.app"
(
    export PATH="$ORIG_PATH"
    RELEASE_SIGNING_PIN_FILE="$PIN_PINNED"
    expect "release verification refuses an ad hoc app, which carries no certificate" refused "no certificate (ad hoc)" release_verify_app "$TMP/adhoc.app"
)
keychain_cases
release_folder_claims
packaging_refusals

passed="$(grep -c '^PASS$' "$RESULTS" || true)"
failed="$(grep -c '^FAIL$' "$RESULTS" || true)"
skipped="$(grep -c '^SKIP$' "$RESULTS" || true)"
print -r -- ""
print -r -- "$passed passed, $failed failed, $skipped skipped"
(( failed == 0 && passed > 0 ))
