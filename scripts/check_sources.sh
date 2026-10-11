#!/bin/zsh
# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.
# Fails on the patterns the codebase forbids:
# - NSLog and print in the app sources (use Log, which keeps interpolated values private);
# - debugPrint, dump, os_log and @State (a stray debug print; Log is the logger; views take models, not local state);
# - privacy: .public on anything but the allow-listed expressions (an error's localizedDescription, a status
#   code, a rawValue), so a path, text or line number never reaches the log in the clear;
# - source files over 400 lines;
# - scripts that fail zsh -n or lack the executable bit.
set -euo pipefail
cd "$(dirname "$0")/.."
problems=0
if grep -nE '\bNSLog\(|(^|[^.[:alnum:]_])print\(' Sources/Nictate/*.swift; then
    echo "ERROR: use Log (os.Logger) instead of NSLog or print"; problems=1
fi
if grep -nE '(^|[^.[:alnum:]_])(debugPrint|dump|os_log)\(|@State( |$)' Sources/Nictate/*.swift; then
    echo "ERROR: use Log instead of debugPrint, dump or os_log; no @State (views take their model through init)"; problems=1
fi
# Every "privacy: .public" must follow an allow-listed expression inside its interpolation.
if grep -nE 'privacy: \.public' Sources/Nictate/*.swift | grep -vE '\\\(([A-Za-z_.]+\.)?(localizedDescription|status|rawValue), privacy: \.public\)'; then
    echo "ERROR: privacy: .public only on localizedDescription, status or rawValue"; problems=1
fi
for script in scripts/build-app.sh Tests/*.sh scripts/*.sh scripts/*.zsh scripts/*.py; do
    [[ -e "$script" ]] || continue
    case "$script" in *.zsh) ;; *) [[ -x "$script" ]] || { echo "ERROR: $script is not executable"; problems=1; } ;; esac
    case "$script" in *.py) ;; *) zsh -n "$script" || { echo "ERROR: $script does not parse"; problems=1; } ;; esac
done
for file in Sources/Nictate/*.swift; do
    lines=$(wc -l < "$file" | tr -d ' ')
    if (( lines > 400 )); then echo "ERROR: $file has $lines lines (limit 400)"; problems=1; fi
done
# A History row takes its identity from its capture's text. A second, index identity lets SwiftUI keep a row for a
# list position, so a delete removes the last row on screen while the store removes the row that was pressed.
if grep -q '\.id(index)' Sources/Nictate/StatusPanelView.swift; then
    echo "ERROR: StatusPanelView.swift must identify History rows by their text, not by index"; problems=1
fi
# The default QA build starts with no synthetic history: a fixture list there would be seeded again on every launch.
# Only that declaration is checked. Tests may still pass their own captures to History.seedFixtures.
if ! grep -qx '    static let historyFixtures: \[String\] = \[\]' scripts/variants/BuildIdentity.test.swift; then
    echo "ERROR: scripts/variants/BuildIdentity.test.swift must declare an empty historyFixtures (QA reseeds synthetic captures otherwise)"; problems=1
fi
# The QA build keeps the production defaults: a startup rule in AppDelegate that writes Save Captures would make a reset
# differ from production. AppDelegate has no reason to mention the setting, so any mention fails, however it is split
# across lines.
if grep -q 'historyEnabled' Sources/Nictate/AppDelegate.swift; then
    echo "ERROR: AppDelegate.swift must not mention historyEnabled (QA defaults must match production)"; problems=1
fi
(( problems == 0 )) && echo "Sources OK"
exit $problems
