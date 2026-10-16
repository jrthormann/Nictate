#!/bin/bash
# Writes code=true or code=false to $GITHUB_OUTPUT (stdout when run locally). code=false only when every changed
# file is documentation, so ci.yml can skip the code jobs. Anything it cannot decide says true.
set -euo pipefail

decide() {
    echo "code=$1 ($2)"
    echo "code=$1" >> "${GITHUB_OUTPUT:-/dev/null}"
}

base="${BASE_SHA:-}"
head="${HEAD_SHA:-}"
if [[ -z "$base" || -z "$head" || "$base" =~ ^0+$ ]]; then
    decide true "no base commit to compare"
    exit 0
fi
# Diffs from the merge base, so a branch behind main sees only its own changes. Renames are off, so a file moved
# out of code shows its old path too.
if ! changed=$(git diff --name-only --no-renames "$base...$head"); then
    decide true "could not diff $base...$head"
    exit 0
fi
if [[ -z "$changed" ]]; then
    decide true "no changed files"
    exit 0
fi
# Documentation paths. Everything else, including .github/, scripts/, Tests/, Sources/ and the Makefile, is code.
if grep -qvE '^(docs/|README\.md$|CHANGELOG\.md$|SECURITY\.md$|CONTRIBUTING\.md$|CODE_OF_CONDUCT\.md$|LICENSE$)' <<< "$changed"; then
    decide true "code changed"
else
    decide false "documentation only"
fi
