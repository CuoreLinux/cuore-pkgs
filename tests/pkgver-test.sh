#!/bin/bash
# bin/pkgver (cuore D160): development builds, candidates and releases get
# versions pacman orders correctly, and a tag that disagrees with the version
# file is refused.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}
check() { # name expected ref
  local got
  got=$("$ROOT/bin/pkgver" "$tmp/src" "$3" 2>&1) || got="error: $got"
  if [[ $got == "$2" ]]; then pass "$1"; else fail "$1 (got $got)"; fi
}

git init -q "$tmp/src"
commit() {
  echo "$1" >"$tmp/src/version"
  git -C "$tmp/src" add version
  git -C "$tmp/src" -c user.name=t -c user.email=t@example.org commit -q --allow-empty -m "$1"
}
commit 0.1.0
commit 0.1.0
check "an untagged commit is a development build" 0.1.0dev2 HEAD

git -C "$tmp/src" tag v0.1.0-rc1
check "a candidate tag gives an attached rc version" 0.1.0rc1 HEAD
commit 0.1.0
git -C "$tmp/src" tag v0.1.0-rc2
git -C "$tmp/src" tag v0.1.0
check "a commit tagged as candidate and release is the release" 0.1.0 HEAD
check "a tag can be named instead of HEAD" 0.1.0rc1 v0.1.0-rc1

commit 0.1.1
check "after a release, development builds work towards the next one" 0.1.1dev4 HEAD
git -C "$tmp/src" tag v0.2.0
check "a tag that disagrees with the version file is refused" "error: v0.2.0 is on a commit whose version file says 0.1.1" HEAD
git -C "$tmp/src" tag -d v0.2.0 >/dev/null

commit 4.0.0.alpha
check "a version file that isn't X.Y.Z is refused" "error: the version file at $(git -C "$tmp/src" rev-parse --short=12 HEAD) doesn't hold X.Y.Z: '4.0.0.alpha'" HEAD

# The order pacman sees: dev < rc < release < the next dev.
if command -v vercmp >/dev/null; then
  order=(0.1.0dev2 0.1.0dev10 0.1.0rc1 0.1.0rc2 0.1.0 0.1.1dev4)
  ok=1
  for ((i = 1; i < ${#order[@]}; i++)); do
    (($(vercmp "${order[i - 1]}" "${order[i]}") < 0)) || ok=0
  done
  if ((ok)); then pass "pacman orders dev < rc < release < next dev"; else fail "pacman orders dev < rc < release < next dev"; fi
else
  printf 'skip - vercmp is missing; ordering not checked\n'
fi

((failures == 0)) || exit 1
