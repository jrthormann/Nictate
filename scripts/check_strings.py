#!/usr/bin/env python3
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

"""Checks localization: every user-facing string in Sources/Nictate/ has an entry in every language
(Sources/Nictate/Resources/en.lproj is the source, es is the translation), all files have identical keys, no translation
is empty, and each translation keeps the placeholders (%@, %d) of its key.

Usage: scripts/check_strings.py [--list]   (--list prints the keys used by the code)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CALLS = r'(?:tr|Text|Toggle|Section|Label|Picker|Button|LabeledContent|TextField|Menu|SettingToggle|SettingRow|SettingCaption|help|accessibilityLabel)'
LITERAL = re.compile(CALLS + r'\(\s*"((?:[^"\\]|\\.)*)"')
# SF Symbol names and similar arguments are not user-facing text.
NON_TEXT_ARGS = re.compile(r'(?:symbol|systemImage|systemSymbolName)\s*:\s*"[^"]*"')
ANY_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
MARKERS = ("LocalizedStringKey(", "title:", "detail:")
TRANSLATIONS = ("es",)
PLACEHOLDER = re.compile(r"%[@d]")
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')


def used_keys():
    keys = set()
    for path in (ROOT / "Sources" / "Nictate").glob("*.swift"):
        text = path.read_text()
        found = list(LITERAL.findall(text))
        for line in text.splitlines():
            if any(m in line for m in MARKERS):
                found += ANY_LITERAL.findall(NON_TEXT_ARGS.sub("", line))
        for key in found:
            if "\\(" in key:      # interpolated: translated via a %@ key instead
                key = re.sub(r"\\\([^)]*\)", "%@", key)
            if re.search(r"[^\W\d_]", key):   # skip empty / symbol-only literals
                keys.add(key)
    return keys


def load(lang):
    path = ROOT / "Sources" / "Nictate" / "Resources" / f"{lang}.lproj" / "Localizable.strings"
    entries = {}
    if path.exists():
        for line in path.read_text().splitlines():
            m = ENTRY.match(line.strip())
            if m:
                entries[m.group(1)] = m.group(2)
    return entries


def main():
    used = used_keys()
    if "--list" in sys.argv:
        print("\n".join(sorted(used)))
        return 0

    en, es = load("en"), load("es")
    problems = []
    ignore = {"Nictate"}   # the product name, shown as a literal where it stands alone
    for key in sorted(used - ignore):
        if key not in en:
            problems.append(f"missing in en: {key!r}")
        if key not in es:
            problems.append(f"missing in es: {key!r}")
    for key in sorted(set(en) ^ set(es)):
        problems.append(f"key only in one language: {key!r}")
    for key, value in en.items():
        if key != value:
            problems.append(f"en must map a key to itself: {key!r}")
    for key, value in es.items():
        if not value.strip():
            problems.append(f"empty es value: {key!r}")
        elif PLACEHOLDER.findall(value) != PLACEHOLDER.findall(key):
            problems.append(f"es placeholders differ from the key: {key!r}")
    for lang in ("fr", "de", "it"):
        if (ROOT / "Sources" / "Nictate" / "Resources" / f"{lang}.lproj").exists():
            problems.append(f"{lang}.lproj should not exist: only en and es ship")

    for p in problems:
        print("ERROR", p)
    print(f"{len(used)} keys used, {len(en)} en, {len(es)} es, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
