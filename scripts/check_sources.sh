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
(( problems == 0 )) && echo "Sources OK"
exit $problems
