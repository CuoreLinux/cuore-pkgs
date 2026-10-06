#!/bin/bash
# bin/build with no package names builds every PKGBUILD here (cuore D133), so
# CI and a full local build miss none.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
listed=$(sed -n '/^PACKAGES=(/,/^)/p' "$ROOT/bin/build" | tr -s ' ()\n' '\n' | grep -v '^PACKAGES=$' | grep -v '^$' | sort)
present=$(find "$ROOT/pkgbuilds" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
if [[ $listed == "$present" ]]; then
  echo "ok - bin/build's list is every PKGBUILD"
else
  echo "not ok - bin/build's list is every PKGBUILD"
  diff <(echo "$listed") <(echo "$present") || true
  exit 1
fi
