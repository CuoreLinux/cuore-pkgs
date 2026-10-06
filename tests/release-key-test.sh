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
"secret set") [[ ${GH_FAIL:-} == 1 ]] && exit 1; [[ $3 == CUORE_SIGNING_KEY && $5 == test/repo ]] && cat >"$GH_SECRET" ;;
*) echo "unexpected gh $*" >&2; exit 99 ;;
esac
SH
chmod +x "$tmp/bin/gh"

# make_key PASSPHRASE AGAIN [env...]: runs the script with the two typed answers.
make_key() {
  local first=$1 second=$2
  shift 2
  printf '%s\n%s\n' "$first" "$second" |
    env HOME="$tmp/home" TMPDIR="$tmp/scratch" PATH="$tmp/bin:$PATH" GH_SECRET="$tmp/secret" \
      CUORE_RELEASE_KEYRING="$tmp/keyring" CUORE_RELEASE_BACKUP="$tmp/backup" CUORE_RELEASE_REPO=test/repo \
      "$@" "$ROOT/bin/make-release-key"
}
nothing_made() {
  [[ ! -e $tmp/keyring && ! -e $tmp/backup && ! -e $tmp/keyring.new && ! -e $tmp/backup.new && ! -e $tmp/secret ]]
}

out=$(make_key test-passphrase other-passphrase 2>&1) || true
if [[ $out == *"passphrases differ"* ]] && nothing_made; then pass "different passphrases make nothing"; else fail "different passphrases make nothing"; fi
out=$(make_key short short 2>&1) || true
if [[ $out == *"shorter than 12"* ]] && nothing_made; then pass "a short passphrase makes nothing"; else fail "a short passphrase makes nothing"; fi
out=$(make_key test-passphrase test-passphrase GH_FAIL=1 2>&1) || true
if nothing_made; then pass "if GitHub refuses the subkey, nothing is kept"; else fail "if GitHub refuses the subkey, nothing is kept"; fi

make_key test-passphrase test-passphrase >"$tmp/out" 2>&1 ||
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
check "the script never makes a keyring in the home folder" test ! -e "$tmp/home/.gnupg"

status=0
out=$(make_key test-passphrase test-passphrase CUORE_RELEASE_BACKUP="$tmp/backup2" 2>&1) || status=$?
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
