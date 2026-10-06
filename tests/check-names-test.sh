#!/bin/bash
# bin/check-names: a package that names the desktop Cuore was forked from is
# refused, wherever the name is (cuore D126).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
name="Omar""chy"
failures=0

pass() { printf 'ok - %s\n' "$1"; }
fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

# make_package NAME: packs $tmp/NAME/ (with a .PKGINFO) as NAME.pkg.tar.zst.
make_package() {
  local dir=$tmp/$1
  mkdir -p "$dir/usr/bin" "$dir/usr/share/man/man1"
  [[ -f $dir/.PKGINFO ]] || printf 'pkgname = %s\npkgdesc = A clean app\n' "$1" >"$dir/.PKGINFO"
  [[ -f $dir/usr/bin/app ]] || printf '\177ELF\0\0clean binary\0' >"$dir/usr/bin/app"
  [[ -f $dir/usr/share/man/man1/app.1.gz ]] || printf '.TH APP 1\nA clean page.\n' | gzip >"$dir/usr/share/man/man1/app.1.gz"
  (cd "$dir" && bsdtar --zstd -cf "$tmp/$1.pkg.tar.zst" .PKGINFO usr)
}

check() { "$ROOT/bin/check-names" "$@" 2>"$tmp/stderr"; }

make_package clean
if check "$tmp/clean.pkg.tar.zst"; then pass "a clean package passes"; else fail "a clean package passes"; fi

refused() {
  local label=$1 package=$2 where=$3
  if check "$tmp/$package.pkg.tar.zst"; then
    fail "$label"
  elif grep -qF "$where" "$tmp/stderr"; then
    pass "$label"
  else
    fail "$label (didn't say where: $(<"$tmp/stderr"))"
  fi
}

mkdir -p "$tmp/readme/usr/share/doc/app"
printf 'Works on %s too.\n' "$name" >"$tmp/readme/usr/share/doc/app/README.md"
make_package readme
refused "a README naming it is refused" readme usr/share/doc/app/README.md

mkdir -p "$tmp/binary/usr/bin"
printf '\177ELF\0\0~/.config/%s/current/theme\0' "${name,,}" >"$tmp/binary/usr/bin/app"
make_package binary
refused "a binary naming it is refused" binary usr/bin/app

mkdir -p "$tmp/man/usr/share/man/man1"
printf '.TH APP 1\nThe active %s theme.\n' "$name" | gzip >"$tmp/man/usr/share/man/man1/app.1.gz"
make_package man
refused "a compressed man page naming it is refused" man usr/share/man/man1/app.1.gz

mkdir -p "$tmp/filename/usr/share/fonts"
printf 'font\n' >"$tmp/filename/usr/share/fonts/app-${name,,}.ttf"
make_package filename
refused "a file named after it is refused" filename "(its name)"

mkdir -p "$tmp/metadata"
printf 'pkgname = metadata\npkgdesc = The %s screenshot tool\n' "$name" >"$tmp/metadata/.PKGINFO"
make_package metadata
refused "metadata naming it is refused" metadata .PKGINFO

if check "$tmp/clean.pkg.tar.zst" "$tmp/readme.pkg.tar.zst"; then
  fail "one bad package among several fails the check"
else
  pass "one bad package among several fails the check"
fi

status=0
"$ROOT/bin/check-names" 2>/dev/null || status=$?
if ((status == 2)); then pass "no package is a usage error"; else fail "no package is a usage error"; fi

# bin/build runs it inside the container before repo-add, on each package.
build=$(<"$ROOT/bin/build")
if grep -q '/check-names' <<<"$build" &&
  [[ $(grep -n 'check-names' <<<"$build" | tail -1 | cut -d: -f1) -lt $(grep -n 'repo-add -q -p' <<<"$build" | cut -d: -f1) ]]; then
  pass "bin/build checks each package before adding it to the repository"
else
  fail "bin/build checks each package before adding it to the repository"
fi

((failures == 0)) || {
  echo "$failures failed" >&2
  exit 1
}
echo "all check-names tests passed"
