#!/bin/bash
# bin/check-signatures and bin/publish (cuore D134), with a throwaway key and a
# fake gh: an unsigned or tampered file stops publishing; the release gets the
# database under the names pacman asks for, uploads come before removals, and
# files the new database no longer names are removed.

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

# A signing key, and a small signed repository.
mkdir -m 700 "$tmp/key"
gpg --homedir "$tmp/key" --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-gen-key "Test <t@example.org>" ed25519 sign 1d 2>/dev/null
gpg --homedir "$tmp/key" --armor --export >"$tmp/key.asc"
mkdir "$tmp/out"
for file in app-1-1-any.pkg.tar.zst cuore.db.tar.gz cuore.files.tar.gz; do
  echo "$file" >"$tmp/out/$file"
  gpg --homedir "$tmp/key" --batch --quiet --detach-sign -o "$tmp/out/$file.sig" "$tmp/out/$file"
done
ln -s cuore.db.tar.gz "$tmp/out/cuore.db"
echo old >"$tmp/out/cuore.db.tar.gz.old"

if "$ROOT/bin/check-signatures" "$tmp/key.asc" "$tmp/out" >/dev/null 2>&1; then
  pass "a signed repository passes"
else fail "a signed repository passes"; fi
cp -r "$tmp/out" "$tmp/tampered"
echo changed >>"$tmp/tampered/app-1-1-any.pkg.tar.zst"
if "$ROOT/bin/check-signatures" "$tmp/key.asc" "$tmp/tampered" 2>/dev/null; then
  fail "a changed package is caught"
else pass "a changed package is caught"; fi
cp -r "$tmp/out" "$tmp/unsigned"
rm "$tmp/unsigned/cuore.db.tar.gz.sig"
if "$ROOT/bin/check-signatures" "$tmp/key.asc" "$tmp/unsigned" 2>/dev/null; then
  fail "an unsigned database is caught"
else pass "an unsigned database is caught"; fi

# The fake gh: a release that exists with an old package, and a call log.
mkdir "$tmp/bin"
cat >"$tmp/bin/gh" <<'SH'
#!/bin/bash
echo "$*" >>"$GH_LOG"
case "$1 $2" in
"release view")
  [[ " $* " == *" --json "* ]] && printf '%s\n' app-0-1-any.pkg.tar.zst app-1-1-any.pkg.tar.zst cuore.db
  exit 0 ;;
"release upload") shift 3; for f in "$@"; do [[ $f == --clobber ]] || basename "$f"; done >"$GH_UPLOADED" ;;
"release delete-asset") ;;
*) echo "unexpected: gh $*" >&2; exit 99 ;;
esac
SH
chmod +x "$tmp/bin/gh"
run_publish() { PATH="$tmp/bin:$PATH" GH_LOG="$tmp/log" GH_UPLOADED="$tmp/uploaded" "$ROOT/bin/publish" "$@"; }

if run_publish stable-x86_64 "$tmp/out" >/dev/null 2>&1; then pass "publishing runs"; else fail "publishing runs"; fi
uploaded=$(sort "$tmp/uploaded" | tr '\n' ' ')
expected="app-1-1-any.pkg.tar.zst app-1-1-any.pkg.tar.zst.sig cuore.db cuore.db.sig cuore.db.tar.gz cuore.db.tar.gz.sig cuore.files cuore.files.sig cuore.files.tar.gz cuore.files.tar.gz.sig "
if [[ $uploaded == "$expected" ]]; then pass "the release gets the packages, the database by pacman's names, and signatures"; else
  fail "the release gets the packages, the database by pacman's names, and signatures"
  echo "    got: $uploaded"
fi
if grep -qx 'release delete-asset stable-x86_64 app-0-1-any.pkg.tar.zst --yes' "$tmp/log" &&
  ! grep -q 'delete-asset.*app-1-1' "$tmp/log"; then
  pass "files the new database no longer names are removed, and only those"
else fail "files the new database no longer names are removed, and only those"; fi
upload_line=$(grep -n '^release upload' "$tmp/log" | cut -d: -f1)
delete_line=$(grep -n '^release delete-asset' "$tmp/log" | head -1 | cut -d: -f1)
if ((upload_line < delete_line)); then pass "uploads come before removals"; else fail "uploads come before removals"; fi
if [[ $(cat "$tmp/uploaded") != *".old"* ]]; then pass "leftover .old files aren't published"; else fail "leftover .old files aren't published"; fi

status=0
run_publish main "$tmp/out" >/dev/null 2>&1 || status=$?
if ((status == 2)); then pass "only channel releases are published to"; else fail "only channel releases are published to"; fi

((failures == 0)) || {
  echo "$failures failed" >&2
  exit 1
}
echo "all publish tests passed"
