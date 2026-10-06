#!/bin/bash
# The two keys (cuore D133, D134): the keyring package ships the release key,
# the one cuore names in default/pacman/signing-key; dev/ holds the development
# key, which only bin/build's own copies of the source and keyring get, for
# local builds that are never published.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
RELEASE=22B9E953F8077DF7868491D2DFD092CE6B437DF6
tmp=$(mktemp -d)
chmod 700 "$tmp"
trap 'gpgconf --homedir "$tmp" --kill all 2>/dev/null; rm -rf "${tmp:?}"' EXIT
failures=0
check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then printf 'ok - %s\n' "$label"; else
    printf 'not ok - %s\n' "$label"
    failures=$((failures + 1))
  fi
}
fingerprint() { gpg --homedir "$tmp" --show-keys --with-colons "$1" 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }'; }

keyring=$ROOT/pkgbuilds/cuore-keyring
dev=$(tr -d '[:space:]' <"$ROOT/dev/signing-key")
check "the keyring package ships the release key" test "$(fingerprint "$keyring/cuore.gpg")" == "$RELEASE"
check "and trusts it fully" grep -qx "$RELEASE:4:" "$keyring/cuore-trusted"
check "and nothing else" test "$(wc -l <"$keyring/cuore-trusted")" == 1
if [[ -f $ROOT/../cuore/default/pacman/signing-key ]]; then
  check "cuore names the same key" test "$(tr -d '[:space:]' <"$ROOT/../cuore/default/pacman/signing-key")" == "$RELEASE"
fi
check "the development key is a different key" test "$dev" != "$RELEASE"
check "dev/ holds it in both forms" \
  bash -c "[[ \$(gpg --homedir '$tmp' --show-keys --with-colons '$ROOT/dev/cuore.gpg' | awk -F: '/^fpr/ { print \$10; exit }') == $dev && \$(gpg --homedir '$tmp' --show-keys --with-colons '$ROOT/dev/signing-key.asc' | awk -F: '/^fpr/ { print \$10; exit }') == $dev ]]"
check "and trusts it in its own trust file" grep -qx "$dev:4:" "$ROOT/dev/cuore-trusted"
check "no PKGBUILD names the development key" bash -c "! grep -rqF '$dev' '$ROOT/pkgbuilds'"
build=$(<"$ROOT/bin/build")
# shellcheck disable=SC2016 # the shell code below is matched, not run
{
  check "development builds swap in the development key, in their own copies" \
    grep -qF 'cp "$ROOT/dev/cuore.gpg" "$ROOT/dev/cuore-trusted" "$work/pkgbuilds/cuore-keyring/"' <<<"$build"
  check "release builds need the release subkey" grep -qF 'gnupg=${GNUPGHOME:?--release needs GNUPGHOME' <<<"$build"
}

((failures == 0)) || {
  echo "$failures failed" >&2
  exit 1
}
echo "all key tests passed"
