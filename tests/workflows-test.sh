#!/bin/bash
# CI conventions (CLAUDE.md): every workflow denies everything at the top with
# `permissions: {}`, every action is pinned to a full commit SHA, and every
# workflow that runs gh names its repository in GH_REPO.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

shopt -s nullglob
workflows=("$ROOT"/.github/workflows/*.yml)
((${#workflows[@]} > 0)) || {
  echo "not ok - there are workflows to check"
  exit 1
}
for workflow in "${workflows[@]}"; do
  name=${workflow#"$ROOT"/}
  grep -qx 'permissions: {}' "$workflow" || {
    echo "not ok - $name starts with permissions: {}"
    failures=$((failures + 1))
  }
  # gh defaults to a repository it guesses from the checkout's remotes; an
  # upstream remote would make that the fork's origin (cuore D176).
  # shellcheck disable=SC2016 # the workflow's own text, ${{ }} and all
  if grep -qE '(^|[[:space:]])gh ' "$workflow" && ! grep -qxF '  GH_REPO: ${{ github.repository }}' "$workflow"; then
    echo "not ok - $name pins gh to its own repository with GH_REPO"
    failures=$((failures + 1))
  fi
  unpinned=$(grep -nE '^\s*-?\s*uses:' "$workflow" | grep -vE 'uses:\s*[^@[:space:]]+@[0-9a-f]{40}(\s|$)' || true)
  [[ -z $unpinned ]] || {
    echo "not ok - $name pins every action to a commit"
    echo "$unpinned"
    failures=$((failures + 1))
  }
done
((failures == 0)) && echo "ok - every workflow denies by default and pins its actions"
((failures == 0))
