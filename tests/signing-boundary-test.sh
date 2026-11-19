#!/bin/bash
# The signing key never enters the container that runs package build code
# (cuore D190). bin/build has two containers: the first builds, with no key;
# the second signs, with no network and no build tool.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0
check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then printf 'ok - %s\n' "$label"; else
    printf 'not ok - %s\n' "$label"
    failures=$((failures + 1))
  fi
}
absent() { ! grep -qE "$1" <<<"$2"; }
present() { grep -qE "$1" <<<"$2"; }

build=$(sed -n '/^# The build container/,/^# The signing container/p' "$ROOT/bin/build")
sign=$(sed -n '/^# The signing container/,$p' "$ROOT/bin/build")

check "bin/build has a build container and a signing container" test -n "$build" -a -n "$sign"
check "the build container runs the package builds" present 'makepkg -s' "$build"
check "the build container is given no key file" absent 'signing\.key' "$build"
check "the build container is given no key name" absent 'KEY=|\$KEY' "$build"
check "the build container imports and signs nothing" absent 'gpg|--sign|repo-add[^|]* -s' "$build"

check "the signing container holds the key" present 'signing\.key:/signing\.key:ro' "$sign"
check "the signing container has no network" present 'podman run --rm --network none' "$sign"
check "the signing container builds and installs nothing" absent 'makepkg|pacman |sudo|/pkgbuilds|/cuore-src' "$sign"
check "the signing container signs only package files in the output" present '\$file == /out/\*\.pkg\.tar\.zst' "$sign"
check "the signing container signs the database" present 'repo-add -q -p -s -k "\$KEY"' "$sign"
check "an unsigned build starts no signing container" present 'if \[\[ -n \$key \]\]; then' "$sign"

((failures == 0)) || {
  echo "$failures failed" >&2
  exit 1
}
echo "all signing boundary tests passed"
