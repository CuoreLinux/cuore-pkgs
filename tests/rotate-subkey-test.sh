#!/bin/bash
# bin/rotate-signing-subkey on a throwaway key (cuore D192): the old subkey is
# revoked, a new one signs, CI's copy holds the new subkey alone and needs no
# passphrase, the key as it was is kept, and a wrong passphrase changes nothing.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
chmod 700 "$tmp"
trap 'for d in "$tmp"/key* "$tmp"/ci; do gpgconf --homedir "$d" --kill all 2>/dev/null || true; done; rm -rf "${tmp:?}"' EXIT
failures=0
check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then printf 'ok - %s\n' "$label"; else
    printf 'not ok - %s\n' "$label"
    failures=$((failures + 1))
  fi
}

pass='a throwaway passphrase'
key="$tmp/key"
install -d -m 700 "$key" "$tmp/ci"
mkdir -p "$tmp/cuore/default/pacman" "$tmp/keyring-package"
quiet=(--homedir "$key" --batch --quiet --pinentry-mode loopback --passphrase "$pass")
gpg "${quiet[@]}" --quick-gen-key "Rotation test <test@example.invalid>" ed25519 cert 2y 2>/dev/null
main=$(gpg --homedir "$key" --list-keys --with-colons | awk -F: '/^fpr/ { print $10; exit }')
gpg "${quiet[@]}" --quick-add-key "$main" ed25519 sign 2y
old=$(gpg --homedir "$key" --list-keys --with-colons "$main" | awk -F: '/^fpr/ { n++; if (n == 2) print $10 }')
echo "$main" >"$tmp/cuore/default/pacman/signing-key"
gpgconf --homedir "$key" --kill all

rotate() {
  CUORE_RELEASE_KEYRING="$key" CUORE_RELEASE_BACKUP="$tmp/backup" CUORE_SRC="$tmp/cuore" \
    CUORE_KEYRING_PACKAGE="$tmp/keyring-package" CUORE_RELEASE_SECRET_FILE="$tmp/ci-subkey.asc" \
    "$ROOT/bin/rotate-signing-subkey" <<<"$1"
}
subkeys() { gpg --homedir "$1" --list-keys --with-colons "$main" | awk -F: '/^sub/ { print $2 }' | tr '\n' ' '; }

before=$(subkeys "$key")
refused() { ! rotate "$1"; }
check "a wrong passphrase is refused" refused 'not the passphrase'
check "a wrong passphrase changes nothing" test "$(subkeys "$key")" = "$before" -a ! -e "$tmp/backup" -a ! -e "$key.new" -a ! -e "$tmp/ci-subkey.asc"

rotate "$pass" >"$tmp/out" 2>&1 || { cat "$tmp/out"; echo "not ok - the rotation runs"; exit 1; }
new=$(sed -n 's/^ *New signing subkey: *\([0-9A-F]\{40\}\).*/\1/p' "$tmp/out")

check "the old subkey is revoked and a new one is valid" test "$(subkeys "$key")" = "r u "
check "the new subkey is not the old one" test -n "$new" -a "$new" != "$old"
check "the key as it was is kept" bash -c "ls -d '$key'.before-* && gpg --homedir \"\$(ls -d '$key'.before-*)\" --list-secret-keys '$main'"
check "the backup holds the public and the secret key" test -s "$tmp/backup/cuore-release-public.asc" -a -s "$tmp/backup/cuore-release-secret.asc"

gpg --homedir "$tmp/ci" --batch --quiet --import "$tmp/ci-subkey.asc" 2>/dev/null
main_secret_missing() { gpg --homedir "$tmp/ci" --list-secret-keys --with-colons | awk -F: '$1 == "sec" { exit ($15 == "#" ? 0 : 1) }'; }
check "CI's copy has no main secret key" main_secret_missing
check "CI's copy holds the new subkey alone" test "$(gpg --homedir "$tmp/ci" --list-secret-keys --with-colons | grep -c '^ssb:')" = 1
check "CI signs without a passphrase" gpg --homedir "$tmp/ci" --batch --pinentry-mode loopback --passphrase '' -u "$new!" --detach-sign -o "$tmp/probe.sig" "$0"

# What installed systems get: the shipped public key says which subkey counts.
install -d -m 700 "$tmp/key-public"
gpg --homedir "$tmp/key-public" --batch --quiet --import "$tmp/cuore/default/pacman/signing-key.asc"
check "the shipped key verifies the new subkey's signature" gpg --homedir "$tmp/key-public" --verify "$tmp/probe.sig" "$0"
check "the shipped key carries the revocation" test "$(subkeys "$tmp/key-public")" = "r - "
check "the keyring package got the same key" bash -c "gpg --show-keys --with-colons '$tmp/keyring-package/cuore.gpg' | grep -q '$new'"

check "a second rotation is refused while the backup is still there" refused "$pass"

((failures == 0)) || {
  echo "$failures failed" >&2
  exit 1
}
echo "all subkey rotation tests passed"
