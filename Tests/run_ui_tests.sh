#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

# UI smoke tests: real AppKit objects (menu bar icon, notes, settings window, shortcut button).
# They need a window server, so they are separate from Tests/run_tests.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
# The SDK that belongs to the active swiftc (Xcode or Command Line Tools); a mismatched pair fails to compile.
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
mkdir -p build/ui
cp Tests/ui_smoke.swift build/ui/main.swift   # top-level code needs a main.swift
sources=(Sources/Nictate/*.swift(N))
sources=(${sources:#*/main.swift})
swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature ImmutableWeakCaptures -enable-upcoming-feature GlobalActorIsolatedTypesUsability -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature ExistentialAny -target "$(uname -m)-apple-macos14.0" \
    "${sources[@]}" build/ui/main.swift -o build/run_ui_tests
# perl's alarm ends a hung run with SIGALRM (status 142); say so instead of leaving a silent failure.
ui_status=0
perl -e 'alarm 120; exec @ARGV' ./build/run_ui_tests || ui_status=$?
if (( ui_status == 142 )); then echo "error: UI tests timed out after 120 s (they need a window server, and nothing may wait on a permission prompt)" >&2; fi
exit $ui_status
