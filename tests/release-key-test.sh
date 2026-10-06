#!/bin/bash
# bin/make-release-key (cuore D133), in throwaway folders with a fake gh: the
# main key only certifies and needs its passphrase; the subkey that goes to
# GitHub signs without one and holds no main key; the backup has the key, its
# public half and a revocation certificate; nothing touches ~/.gnupg.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
cleanup() {
  for dir in "$tmp/keyring" "$tmp/ci" "$tmp/check"; do
    [[ -d $dir ]] && gpgconf --homedir "$dir" --kill all 2>/dev/null
  done
  rm -rf "${tmp:?}"
}
trap cleanup EXIT
failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}
check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/scratch"
cat >"$tmp/bin/gh" <<'SH'
#!/bin/bash
case "$1 $2" in
"auth status") exit 0 ;;
"secret set") [[ $3 == CUORE_SIGNING_KEY && $5 == test/repo ]] && cat >"$GH_SECRET" ;;
*) echo "unexpected gh $*" >&2; exit 99 ;;
esac
SH
chmod +x "$tmp/bin/gh"

before=$(stat -c %Y "$HOME/.gnupg" 2>/dev/null || echo none)
HOME=$tmp/home TMPDIR=$tmp/scratch PATH="$tmp/bin:$PATH" GH_SECRET=$tmp/secret \
  CUORE_RELEASE_KEYRING=$tmp/keyring CUORE_RELEASE_BACKUP=$tmp/backup CUORE_RELEASE_REPO=test/repo \
  CUORE_RELEASE_TEST_PASSPHRASE=test-passphrase "$ROOT/bin/make-release-key" >"$tmp/out" 2>&1 ||
  {
    cat "$tmp/out"
    fail "the script runs"
  }

main=$(gpg --homedir "$tmp/keyring" --list-keys --with-colons | awk -F: '/^fpr/ { print $10; exit }')
check "the key is made, with Cuore's identity" \
  bash -c "gpg --homedir '$tmp/keyring' --list-keys --with-colons | grep -q '^uid:.*Cuore Linux package signing <hello@antoniopiattelli.com>'"
check "the main key only certifies" \
  bash -c "gpg --homedir '$tmp/keyring' --list-keys --with-colons | grep -E '^pub:' | cut -d: -f12 | grep -qx 'cSC'"
check "both keys expire in about two years" \
  bash -c "gpg --homedir '$tmp/keyring' --list-keys --with-colons | awk -F: '/^(pub|sub):/ { d = (\$7 - systime()) / 86400; if (d < 725 || d > 735) bad = 1 } END { exit bad }'"

echo signed >"$tmp/file"
gpgconf --homedir "$tmp/keyring" --kill all 2>/dev/null || true
check "your copy needs the passphrase" \
  bash -c "! gpg --homedir '$tmp/keyring' --batch --pinentry-mode loopback --passphrase '' -u '$main' --detach-sign -o '$tmp/x.sig' '$tmp/file'"
check "your copy signs with it" \
  gpg --homedir "$tmp/keyring" --batch --pinentry-mode loopback --passphrase test-passphrase -u "$main" --detach-sign -o "$tmp/y.sig" "$tmp/file"

mkdir -m 700 "$tmp/ci"
gpg --homedir "$tmp/ci" --batch --quiet --import "$tmp/secret" 2>/dev/null || true
check "GitHub gets a subkey, not the main key" \
  bash -c "gpg --homedir '$tmp/ci' --list-secret-keys --with-colons | grep -q '^sec:' && gpg --homedir '$tmp/ci' -K | grep -q '^sec#'"
check "GitHub's subkey signs without a passphrase" \
  gpg --homedir "$tmp/ci" --batch --pinentry-mode error -u "$main" --detach-sign -o "$tmp/ci.sig" "$tmp/file"
check "what it signs checks out against the public key" \
  gpg --homedir "$tmp/keyring" --verify "$tmp/ci.sig" "$tmp/file"

check "the backup has the key, its public half and a revocation certificate" \
  test -s "$tmp/backup/cuore-release-secret.asc" -a -s "$tmp/backup/cuore-release-public.asc" -a -s "$tmp/backup/cuore-release-revocation.asc"
mkdir -m 700 "$tmp/check"
gpg --homedir "$tmp/check" --batch --quiet --import "$tmp/backup/cuore-release-secret.asc" 2>/dev/null || true
check "the backup is protected by the passphrase" \
  bash -c "! gpg --homedir '$tmp/check' --batch --pinentry-mode loopback --passphrase '' -u '$main' --detach-sign -o '$tmp/z.sig' '$tmp/file'"
check "the throwaway keyring is gone" test -z "$(find "$tmp/scratch" -mindepth 1 -print -quit)"
check "the home keyring (\$HOME/.gnupg) is untouched" test "$before" == "$(stat -c %Y "$HOME/.gnupg" 2>/dev/null || echo none)"

status=0
out=$(HOME=$tmp/home PATH="$tmp/bin:$PATH" CUORE_RELEASE_KEYRING=$tmp/keyring CUORE_RELEASE_BACKUP=$tmp/backup2 \
  CUORE_RELEASE_REPO=test/repo "$ROOT/bin/make-release-key" 2>&1) || status=$?
if ((status != 0)) && [[ $out == *"already holds a key"* ]]; then
  pass "a second key is refused"
else
  fail "a second key is refused"
fi

((failures == 0)) || {
  echo "$failures failed" >&2
  exit 1
}
echo "all release-key tests passed"
