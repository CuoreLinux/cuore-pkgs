#!/bin/bash
# Every source a PKGBUILD downloads is pinned (cuore D133); files in this
# repository are pinned by git. A download has a real checksum, so a changed
# file fails the build; a git source names a commit, or a tag with a checksum
# of its tree (makepkg checks those since pacman 6.1).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

# sources PKGBUILD: one "source<TAB>checksum" line per source.
sources() {
  (
    unset CUORE_SRC
    export CARCH=x86_64
    local source=() sha256sums=()
    # shellcheck disable=SC1090
    . "$1"
    for i in "${!source[@]}"; do
      printf '%s\t%s\n' "${source[i]}" "${sha256sums[i]:-}"
    done
  )
}

check_pkgbuild() {
  local pkgbuild=$1 entry sum url problems=()
  while IFS=$'\t' read -r entry sum; do
    url=${entry#*::}
    if [[ $url != *://* ]]; then
      continue # a file in this repository: git pins it
    elif [[ $url == git+* ]]; then
      if [[ $url != *"#commit="* && ! ($url == *"#tag="* && $sum != SKIP && -n $sum) ]]; then
        problems+=("$entry: git source without a commit, or a tag without a checksum")
      fi
    elif [[ $sum == SKIP || -z $sum ]]; then
      problems+=("$entry: download without a checksum")
    fi
  done < <(sources "$pkgbuild")
  if ((${#problems[@]})); then
    printf 'not ok - %s\n' "${pkgbuild#"$ROOT"/}"
    printf '    %s\n' "${problems[@]}"
    return 1
  fi
  printf 'ok - %s\n' "${pkgbuild#"$ROOT"/}"
}

for pkgbuild in "$ROOT"/pkgbuilds/*/PKGBUILD; do
  check_pkgbuild "$pkgbuild" || failures=$((failures + 1))
done

# The check itself: an unpinned source is refused.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/PKGBUILD" <<'EOF'
source=("a.tar.gz::https://example.org/a.tar.gz" "b::git+https://example.org/b.git#tag=1" "c::git+https://example.org/c.git")
sha256sums=('SKIP' 'SKIP' 'SKIP')
EOF
if check_pkgbuild "$tmp/PKGBUILD" >"$tmp/out" || [[ $(grep -c '^    ' "$tmp/out") != 3 ]]; then
  echo "not ok - unpinned sources are refused"
  cat "$tmp/out"
  failures=$((failures + 1))
else
  echo "ok - unpinned sources are refused"
fi

((failures == 0)) || {
  echo "$failures failed" >&2
  exit 1
}
echo "all pinned-sources tests passed"
