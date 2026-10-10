#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

set -euo pipefail
cd "$(dirname "$0")/.."
# The SDK that belongs to the active swiftc (Xcode or Command Line Tools); a mismatched pair fails to compile.
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
mkdir -p build/tests
cp Tests/run_tests.swift build/tests/main.swift   # top-level code needs a main.swift
# TEST_ARCH=x86_64 builds the Intel runner; on Apple silicon it runs under Rosetta.
ARCH="${TEST_ARCH:-$(uname -m)}"
# Every source except main.swift (the app entry point); the test runner supplies its own main.swift.
sources=(Sources/Nictate/*.swift(N))
sources=(${sources:#*/main.swift})
# OPT=-O builds the runner optimized, as the shipped app is; the default keeps the build quick.
swiftc ${=OPT:-} -wmo -swift-version 5 -warnings-as-errors -strict-concurrency=complete -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature ImmutableWeakCaptures -enable-upcoming-feature GlobalActorIsolatedTypesUsability -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature ExistentialAny -target "$ARCH-apple-macos14.0" "${sources[@]}" build/tests/main.swift -o build/run_tests 2> build/tests/stderr.txt || { cat build/tests/stderr.txt >&2; exit 1; }
grep -v "libswiftCompatibilityPacks" build/tests/stderr.txt >&2 || true
arch -"$ARCH" ./build/run_tests
