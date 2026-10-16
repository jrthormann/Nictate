#!/bin/bash
# Tests scripts/ci_code_changed.sh against a throwaway repository, so a change to which files skip CI is caught.
# The repository lives in a temporary directory and is removed when the script ends.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
detector="$here/scripts/ci_code_changed.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

repo="$work/repo"
git -c init.defaultBranch=main init -q "$repo"
cd "$repo"
git config user.name test
git config user.email test@example.com
git config commit.gpgsign false

# Appends a line to each named file, commits them, and prints the new commit.
make_commit() {
    local message=$1
    shift
    local file
    for file in "$@"; do
        mkdir -p "$(dirname "$file")"
        echo "$message" >> "$file"
    done
    git add -A
    git commit -q -m "$message"
    git rev-parse HEAD
}

# Runs the detector on BASE..HEAD and expects it to write code=EXPECTED.
check() {
    local label=$1 base=$2 head=$3 expected=$4
    local output got
    output=$(mktemp "$work/out.XXXXXX")
    BASE_SHA="$base" HEAD_SHA="$head" GITHUB_OUTPUT="$output" bash "$detector" > /dev/null 2>&1 || true
    got=$(sed -n 's/^code=//p' "$output" | tail -n 1)
    if [[ "$got" == "$expected" ]]; then
        echo "ok    $label -> code=$got"
    else
        echo "FAIL  $label: expected code=$expected, got '${got:-nothing}'"
        failures=$((failures + 1))
    fi
}

start=$(make_commit "initial" README.md docs/guide.md Sources/Nictate/App.swift .github/workflows/ci.yml)
docs=$(make_commit "docs only" docs/guide.md README.md)
legal=$(make_commit "legal notices and images" LICENSE CHANGELOG.md docs/images/flag.svg)
code=$(make_commit "code only" Sources/Nictate/App.swift)
workflow=$(make_commit "workflow only" .github/workflows/ci.yml)
gate=$(make_commit "gate script only" scripts/ci_code_changed.sh)
mixed=$(make_commit "docs and code" docs/guide.md Sources/Nictate/App.swift)
# A code file moved into docs/ removes code, so it must still count as code.
git mv Sources/Nictate/App.swift docs/App.swift
git commit -q -m "rename code into docs"
renamed=$(git rev-parse HEAD)
# A documentation branch cut from before a code change on main must not inherit that change.
git checkout -q -b docs-branch "$start"
docs_branch=$(make_commit "docs on a branch" docs/guide.md)
git checkout -q --detach "$renamed"
zero=0000000000000000000000000000000000000000
unknown=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef

check "documentation only"          "$start"  "$docs"  false
check "legal notices and images"    "$docs"   "$legal" false
check "code only"                   "$legal"  "$code"  true
check "workflow file only"          "$code"   "$workflow" true
check "gate script only"            "$workflow" "$gate" true
check "documentation and code"      "$gate"   "$mixed" true
check "code renamed into docs"      "$mixed"  "$renamed" true
check "docs branch behind code"     "$renamed" "$docs_branch" false
check "zero base (new branch)"      "$zero"   "$mixed" true
check "unknown base commit"         "$unknown" "$mixed" true
check "empty range"                 "$mixed"  "$mixed" true

if (( failures > 0 )); then
    echo "$failures change-detector check(s) failed"
    exit 1
fi
echo "all change-detector checks passed"
