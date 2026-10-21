# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# Signing rules, sourced after scripts/signing_keychain.zsh by scripts/build-app.sh and scripts/build-dmg.sh.
# Callers set NICTATE_SIGN_FLAGS (an array) before calling the sign functions.
#
# A release is signed only with the certificate whose SHA-1 is pinned in scripts/release-signing.txt, and only from
# the dedicated keychain. It never falls back to another certificate: a different signing identity makes macOS ask
# every user for Screen Recording again. Development and QA builds keep their fallbacks, and say which one they used.
# make dmg reads the pin from the commit it packages (docs/RELEASING.md).

RELEASE_PIN_LABEL="scripts/release-signing.txt"
RELEASE_SIGNING_PIN_FILE="${RELEASE_SIGNING_PIN_FILE:-$RELEASE_PIN_LABEL}"

release_fail() {
    print -r -- "error: $*" >&2
    return 1
}

# Prints the pinned SHA-1 in upper case. Fails unless the pin file holds one line: "SHA-1" and 40 hex digits.
release_pinned_sha1() {
    local sha="" re='^[0-9A-Fa-f]{40}$'
    if [[ -f "$RELEASE_SIGNING_PIN_FILE" ]]; then
        sha="$(awk '$1 == "SHA-1" && NF == 2 { print $2 }' "$RELEASE_SIGNING_PIN_FILE")"
    fi
    [[ "$sha" =~ $re ]] || return 1
    print -r -- "${(U)sha}"
}

# Prints the SHA-1 of each certificate named NICTATE_SIGNING_NAME in the dedicated keychain, one per line.
# Certificate fingerprints are public; no key material is read.
release_keychain_sha1s() {
    [[ -f "$NICTATE_SIGNING_KEYCHAIN" ]] || return 0
    security find-certificate -a -c "$NICTATE_SIGNING_NAME" -Z "$NICTATE_SIGNING_KEYCHAIN" 2>/dev/null \
        | awk '/^SHA-1 hash:/ { print $3 }' || true
}

# Prints the SHA-1 of the leaf certificate that signed APP. Prints nothing when APP has no certificate (ad hoc).
release_leaf_sha1() {
    local dir sha=""
    dir="$(mktemp -d)" || return 1
    codesign -d --extract-certificates="$dir/leaf" "$1" >/dev/null 2>&1 || true
    if [[ -f "$dir/leaf0" ]]; then
        sha="$(shasum -a 1 "$dir/leaf0" | awk '{ print toupper($1) }')"
    fi
    rm -rf "$dir"
    print -r -- "$sha"
}

# Checks APP before it is packaged, or once it is attached: it must pass strict code-signature verification, and it
# must be signed with the pinned certificate.
release_verify_app() {
    local app="$1" pin actual
    pin="$(release_pinned_sha1)" || { release_fail "$RELEASE_PIN_LABEL must hold one line: SHA-1 and 40 hex digits"; return 1; }
    if ! codesign --verify --strict "$app" >/dev/null 2>&1; then
        release_fail "$app does not pass codesign --verify --strict, so nothing was packaged"
        return 1
    fi
    actual="$(release_leaf_sha1 "$app")"
    if [[ "$actual" != "$pin" ]]; then
        release_fail "$app is signed with ${actual:-no certificate (ad hoc)}, not the pinned certificate $pin, so nothing was packaged"
        return 1
    fi
    print -r -- "signed with the pinned certificate $pin"
}

# Signs APP for a release: the pinned certificate from the dedicated keychain, and nothing else. Fails without signing
# when the pin, the keychain, the certificate, or its password is not in order.
sign_for_release() {
    local app="$1" pin found
    pin="$(release_pinned_sha1)" || { release_fail "$RELEASE_PIN_LABEL must hold one line: SHA-1 and 40 hex digits"; return 1; }
    if [[ -n "${SIGN_IDENTITY:-}" ]]; then
        release_fail "SIGN_IDENTITY is not used for releases; the certificate is the one pinned in $RELEASE_PIN_LABEL"
        return 1
    fi
    if [[ ! -f "$NICTATE_SIGNING_KEYCHAIN" ]]; then
        release_fail "the release signing keychain $NICTATE_SIGNING_KEYCHAIN does not exist, so nothing was signed or packaged. Put the certificate pinned in $RELEASE_PIN_LABEL (SHA-1 $pin) in that keychain, then build again. docs/RELEASING.md, \"Signing identity\", explains how."
        return 1
    fi
    found="$(release_keychain_sha1s)"
    if [[ -z "$found" ]]; then
        release_fail "$NICTATE_SIGNING_KEYCHAIN has no certificate named \"$NICTATE_SIGNING_NAME\", so nothing was signed. Put the certificate pinned in $RELEASE_PIN_LABEL (SHA-1 $pin) there."
        return 1
    fi
    if [[ "$found" == *$'\n'* ]]; then
        release_fail "$NICTATE_SIGNING_KEYCHAIN holds more than one certificate named \"$NICTATE_SIGNING_NAME\", so the release identity is ambiguous and nothing was signed. Keep only the pinned certificate there."
        return 1
    fi
    if [[ "$found" != "$pin" ]]; then
        release_fail "$NICTATE_SIGNING_KEYCHAIN holds \"$NICTATE_SIGNING_NAME\" with SHA-1 $found, but $RELEASE_PIN_LABEL pins $pin, so nothing was signed. Put the pinned certificate there, or pin the new one on purpose (docs/RELEASING.md)."
        return 1
    fi
    if ! signing_keychain_unlock; then
        release_fail "the release signing keychain is locked and was not unlocked, so nothing was signed. A release is never signed with another certificate. Run make dmg in Terminal and enter the keychain's password when asked."
        return 1
    fi
    if ! codesign "${NICTATE_SIGN_FLAGS[@]}" --keychain "$NICTATE_SIGNING_KEYCHAIN" --sign "$pin" "$app"; then
        release_fail "codesign could not sign $app with the pinned certificate from $NICTATE_SIGNING_KEYCHAIN, so nothing was packaged"
        return 1
    fi
    release_verify_app "$app"
}

# Prints success when VERSION is a prerelease: a beta, which has a suffix after the number, as in 1.0.0-beta.5. A version
# without a suffix is a stable release and always uses the pinned certificate.
release_is_prerelease() {
    [[ "$1" == *-* ]]
}

# Checks APP for an ad-hoc prerelease: strict code-signature verification passes, and the signature names no certificate.
release_verify_adhoc() {
    local app="$1" actual
    if ! codesign --verify --strict "$app" >/dev/null 2>&1; then
        release_fail "$app does not pass codesign --verify --strict, so nothing was packaged"
        return 1
    fi
    actual="$(release_leaf_sha1 "$app")"
    if [[ -n "$actual" ]]; then
        release_fail "$app is signed with a certificate ($actual), not ad hoc, so nothing was packaged"
        return 1
    fi
    print -r -- "signed ad hoc, as a prerelease"
}

# Signs APP for a prerelease with an ad-hoc signature: no keychain and no certificate. The signature differs on every
# build, so macOS asks each user to grant Screen Recording again after an update. Stable releases never use this.
sign_for_prerelease() {
    local app="$1"
    if ! codesign "${NICTATE_SIGN_FLAGS[@]}" --sign - "$app"; then
        release_fail "codesign could not sign $app ad hoc, so nothing was packaged"
        return 1
    fi
    release_verify_adhoc "$app"
}

# Signs APP for development and QA: SIGN_IDENTITY if set, else the dedicated keychain, else the login-keychain
# certificate with the same name (with a warning), else ad hoc (with a warning). Never used for releases.
sign_for_development() {
    local app="$1" identity="${SIGN_IDENTITY:-}" hash="" valid="" signed=""
    # Only valid code-signing identities count for the login-keychain fallback: a certificate without its key shows up
    # in find-certificate but cannot sign.
    valid="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    if [[ -z "$identity" ]] && hash="$(signing_keychain_hash)"; then
        # Signing by hash: the login keychain may hold an older certificate with the same name.
        if signing_keychain_unlock && codesign "${NICTATE_SIGN_FLAGS[@]}" --keychain "$NICTATE_SIGNING_KEYCHAIN" --sign "$hash" "$app"; then
            signed=1
        else
            echo "warning: could not sign from $NICTATE_SIGNING_KEYCHAIN, trying the fallback identities" >&2
        fi
    fi
    if [[ -n "$signed" ]]; then
        return 0
    fi
    if [[ -z "$identity" && "$valid" == *"\"$NICTATE_SIGNING_NAME\""* ]]; then
        identity="$NICTATE_SIGNING_NAME"
        echo "warning: signing with the login-keychain certificate named \"$NICTATE_SIGNING_NAME\", not the one in $NICTATE_SIGNING_KEYCHAIN. Development builds only: releases never use it." >&2
    fi
    if [[ -n "$identity" && "$valid" == *"\"$identity\""* ]]; then
        codesign "${NICTATE_SIGN_FLAGS[@]}" --sign "$identity" "$app"
    else
        echo "warning: no local signing identity found (run make setup), signing ad-hoc (permissions may reset on each build)" >&2
        codesign "${NICTATE_SIGN_FLAGS[@]}" --sign - "$app"
    fi
}

# Checks a build number for a version against the release list (scripts/release-builds.txt, read from the commit).
# Each line is "VERSION BUILD", in release order. The build must be the one listed for the version, and it must be
# higher than the builds on the lines above it, so a build number cannot repeat or regress. Lines below it are later
# releases and do not constrain it.
release_check_build_number() {
    local version="$1" build="$2" list="$3" v b rest found="" prev=0 seen=0
    case "$build" in
        ''|*[!0-9]*|0*) release_fail "BUILD_NUMBER must be a whole number without leading zeros, not '$build'"; return 1 ;;
    esac
    if [[ ! -f "$list" ]]; then
        release_fail "the release list $list is missing; it must name $version and its approved build"
        return 1
    fi
    while read -r v b rest; do
        if [[ -z "$v" || "$v" == \#* ]]; then
            continue
        fi
        if [[ -z "$b" || -n "$rest" ]]; then
            release_fail "$list: '$v' must be followed by one build number, as in '$v 22'"
            return 1
        fi
        case "$b" in
            *[!0-9]*|0*) release_fail "$list: the build for $v is '$b', which is not a whole number without leading zeros"; return 1 ;;
        esac
        if [[ "$v" == "$version" ]]; then
            if (( seen )); then
                release_fail "$list lists $version more than once"
                return 1
            fi
            seen=1
            found="$b"
        elif (( ! seen )) && (( b > prev )); then
            prev="$b"
        fi
    done < "$list"
    if (( ! seen )); then
        release_fail "$version is not in $list; add the line '$version <approved build>' there before packaging"
        return 1
    fi
    if [[ "$build" != "$found" ]]; then
        release_fail "$version is approved for build $found, not BUILD_NUMBER=$build (see $list)"
        return 1
    fi
    if (( found <= prev )); then
        release_fail "build $found for $version does not exceed build $prev of an earlier release (see $list)"
        return 1
    fi
    print -r -- "build $found for $version is approved"
}

# Claims the release folder DIR for this build. mkdir fails when DIR exists, so nothing from an earlier release is touched.
# When this call creates DIR it records DIR in CREATED_RELEASE, which the build's EXIT cleanup removes on failure. Returns
# 0 only when this call created DIR. The claim cannot be cut between the two steps: mkdir runs with INT, TERM and HUP
# ignored (the subshell's ignored signals are inherited by mkdir, so one cannot abort it midway), and a signal that
# reaches the shell during the claim only sets a flag. The shell then exits 130 once the claim is recorded, so the cleanup
# always sees the folder this call created, and never a folder another process created.
claim_release_folder() {
    local dir="$1" interrupted=""
    trap 'interrupted=1' INT TERM HUP
    if ( trap '' INT TERM HUP; mkdir "$dir" ) 2>/dev/null; then
        CREATED_RELEASE="$dir"
    fi
    trap 'exit 130' INT TERM HUP
    [[ -z "$interrupted" ]] || exit 130
    [[ "${CREATED_RELEASE:-}" == "$dir" ]]
}
