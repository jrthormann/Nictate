# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# Sourced by scripts/create_signing_cert.sh and scripts/build-app.sh. The signing identity lives in its own keychain,
# outside the login keychain and outside the keychain search list, so it is usable only while that
# keychain is unlocked, and only by codesign (and other Apple tools) given its path.

# Both can be overridden from the environment, which the scripts' own checks use with a scratch keychain.
NICTATE_SIGNING_NAME="${NICTATE_SIGNING_NAME:-Nictate Local Signing}"
NICTATE_SIGNING_KEYCHAIN="${NICTATE_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/nictate-signing.keychain-db}"

# Quotes a value for one line of `security -i`, which honors double quotes and backslash escapes.
# Passwords travel on its standard input, so they never show up in another process's `ps` listing.
signing_quote() {
    local value=${1//\\/\\\\}
    print -r -- "\"${value//\"/\\\"}\""
}

# Runs `security -i` commands given as lines on standard input; their output is noise (attribute dumps).
signing_security() {
    security -i >/dev/null
}

# Exit status 0 when the keychain is unlocked, 1 when locked, 2 when it cannot be opened (missing).
# Asks SecKeychainGetStatus directly: `security show-keychain-info` on a locked keychain raises a GUI
# password dialog, and codesign on a locked one fails with errSecInternalComponent.
signing_keychain_status() {
    /usr/bin/python3 -c 'import ctypes, sys
sec = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
ref, status = ctypes.c_void_p(), ctypes.c_uint32(0)
if sec.SecKeychainOpen(sys.argv[1].encode(), ctypes.byref(ref)) or sec.SecKeychainGetStatus(ref, ctypes.byref(status)):
    sys.exit(2)
sys.exit(0 if status.value & 1 else 1)' "$NICTATE_SIGNING_KEYCHAIN"
}

# Prints the SHA-1 of the identity in the dedicated keychain; fails when the keychain or certificate is
# missing. Reading a certificate works on a locked keychain and never prompts.
signing_keychain_hash() {
    [[ -f "$NICTATE_SIGNING_KEYCHAIN" ]] || return 1
    security find-certificate -c "$NICTATE_SIGNING_NAME" -Z "$NICTATE_SIGNING_KEYCHAIN" 2>/dev/null \
        | awk '/^SHA-1 hash:/ { print $3; found = 1 } END { exit !found }'
}

# Unlocks the dedicated keychain with a password read from the terminal, at most three tries.
# Returns 1 without asking when there is no terminal, and when the user presses Return to skip.
signing_keychain_unlock() {
    local state=0
    signing_keychain_status || state=$?
    (( state == 0 )) && return 0
    (( state == 1 )) || return 1
    if [[ ! -t 0 ]]; then
        echo "note: the Nictate signing keychain is locked and there is no terminal to ask for its password" >&2
        return 1
    fi
    echo "The Nictate signing keychain is locked (it locks when the Mac sleeps)." >&2
    echo "Enter its password to sign with \"$NICTATE_SIGNING_NAME\", or press Return to skip." >&2
    local password attempt
    for attempt in 1 2 3; do
        # zsh shows a `read "name?prompt"` prompt only in interactive shells, so print it here.
        printf 'Signing keychain password: ' >&2
        read -rs password || password=""
        echo >&2
        [[ -n "$password" ]] || return 1
        print -r -- "unlock-keychain -p $(signing_quote "$password") $(signing_quote "$NICTATE_SIGNING_KEYCHAIN")" \
            | signing_security 2>/dev/null
        signing_keychain_status && return 0
        echo "That password did not unlock it." >&2
    done
    return 1
}
