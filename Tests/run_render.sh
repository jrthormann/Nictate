#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# Offscreen renders of the selection overlay, for review by eye: a PNG and an 8x corner crop per case, written to
# NICTATE_RENDER_DIR, then four self-checks. Needs no window server, and is not part of make check.
# Exit status: 0 when every check passes, 1 when one fails, 2 when the folder is unset or inside the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
root=${PWD:A}

if [[ -z ${NICTATE_RENDER_DIR:-} ]]; then
    echo "error: NICTATE_RENDER_DIR is not set; give a folder outside the repository, for example <scratchpad>/capture-render/before" >&2
    exit 2
fi
render_dir=${NICTATE_RENDER_DIR:A}
# The PNGs never belong in the repository, neither in this worktree nor in the main checkout that holds its git data.
repos=($root)
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [[ -n $common ]]; then repos+=(${common:h}); fi
for repo in $repos; do
    if [[ $render_dir == "$repo" || $render_dir == "$repo"/* ]]; then
        echo "error: NICTATE_RENDER_DIR ($render_dir) is inside the repository ($repo); choose a folder outside it" >&2
        exit 2
    fi
done
mkdir -p "$render_dir"

# The SDK that belongs to the active swiftc (Xcode or Command Line Tools); a mismatched pair fails to compile.
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
mkdir -p build/render
cp Tests/render_capture.swift build/render/main.swift   # top-level code needs a main.swift
sources=(Sources/Nictate/*.swift(N))
sources=(${sources:#*/main.swift})
# OPT=-O by default: the checks read every pixel of 64 renders, which is slow unoptimized.
swiftc ${=OPT:--O} -wmo -swift-version 5 -warnings-as-errors -strict-concurrency=complete -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature ImmutableWeakCaptures -enable-upcoming-feature GlobalActorIsolatedTypesUsability -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature ExistentialAny -target "$(uname -m)-apple-macos14.0" \
    "${sources[@]}" build/render/main.swift -o build/run_render
NICTATE_RENDER_DIR="$render_dir" ./build/run_render
