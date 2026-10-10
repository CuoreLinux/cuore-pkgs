#!/bin/bash
# bin/key-expiry (cuore D162): a key far from expiry passes, one whose subkey
# expires soon fails, and the shipped keyring is read by default.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
chmod 700 "$tmp"
trap 'gpgconf --homedir "$tmp/key" --kill all 2>/dev/null; rm -rf "${tmp:?}"' EXIT
failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

mkdir -m 700 "$tmp/key"
gpg --homedir "$tmp/key" --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-gen-key "Test <t@example.org>" ed25519 cert 2y 2>/dev/null
fpr=$(gpg --homedir "$tmp/key" --list-keys --with-colons 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
gpg --homedir "$tmp/key" --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-add-key "$fpr" ed25519 sign 30d 2>/dev/null
gpg --homedir "$tmp/key" --export "$fpr" >"$tmp/key.gpg"

if "$ROOT/bin/key-expiry" --days 10 "$tmp/key.gpg" >/dev/null 2>&1; then
  pass "a key a month from expiry passes a 10-day check"
else fail "a key a month from expiry passes a 10-day check"; fi
if ! "$ROOT/bin/key-expiry" "$tmp/key.gpg" >/dev/null 2>&1; then
  pass "a subkey expiring within 90 days fails, though its main key lasts longer"
else fail "a subkey expiring within 90 days fails, though its main key lasts longer"; fi
if "$ROOT/bin/key-expiry" | grep -q '^Cuore.s signing key expires on 20'; then
  pass "the shipped keyring is read by default"
else fail "the shipped keyring is read by default"; fi

((failures == 0)) || exit 1
