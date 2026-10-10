#!/bin/bash
# bin/promote (cuore D160), with a throwaway key and a fake gh: stable gets the
# rc files unchanged; a development build, a candidate without
# --allow-candidate, and a bad signature are all refused before anything is
# published.

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
  --quick-gen-key "Test <t@example.org>" ed25519 sign 1d 2>/dev/null
gpg --homedir "$tmp/key" --armor --export >"$tmp/key.asc"

rc_release() { # the rc release's files, with cuore at VERSION
  rm -rf "$tmp/rc"
  mkdir "$tmp/rc"
  for file in "cuore-$1-1-x86_64.pkg.tar.zst" "cuore-settings-$1-1-any.pkg.tar.zst" cuore.db.tar.gz cuore.files.tar.gz; do
    echo "$file" >"$tmp/rc/$file"
    gpg --homedir "$tmp/key" --batch --quiet --detach-sign -o "$tmp/rc/$file.sig" "$tmp/rc/$file"
  done
  cp "$tmp/rc/cuore.db.tar.gz" "$tmp/rc/cuore.db"
  cp "$tmp/rc/cuore.db.tar.gz.sig" "$tmp/rc/cuore.db.sig"
}

mkdir "$tmp/bin"
cat >"$tmp/bin/gh" <<'SH'
#!/bin/bash
echo "$*" >>"$GH_LOG"
case "$1 $2" in
"release download") [[ $3 == rc-x86_64 ]] || exit 98; cp "$RC_DIR"/* "$5"/ ;;
"release view") [[ " $* " == *" --json "* ]] && echo old-1-1-any.pkg.tar.zst; exit 0 ;;
"release upload") shift 3; for f in "$@"; do [[ $f == --clobber ]] || basename "$f"; done >"$GH_UPLOADED" ;;
"release delete-asset") ;;
*) echo "unexpected: gh $*" >&2; exit 99 ;;
esac
SH
chmod +x "$tmp/bin/gh"
promote() {
  : >"$tmp/log"
  : >"$tmp/uploaded"
  PATH="$tmp/bin:$PATH" GH_LOG="$tmp/log" GH_UPLOADED="$tmp/uploaded" RC_DIR="$tmp/rc" \
    "$ROOT/bin/promote" "$tmp/key.asc" "$@" >/dev/null 2>&1
}
published() { grep -q '^release upload stable-x86_64' "$tmp/log"; }

rc_release 0.1.0
if promote && published && grep -qx 'cuore-0.1.0-1-x86_64.pkg.tar.zst' "$tmp/uploaded"; then
  pass "a release on rc is published to stable unchanged"
else fail "a release on rc is published to stable unchanged"; fi
if ! grep -q 'release upload rc' "$tmp/log"; then pass "rc itself is left alone"; else fail "rc itself is left alone"; fi

rc_release 0.1.0rc1
if ! promote && ! published; then pass "a candidate isn't promoted by default"; else fail "a candidate isn't promoted by default"; fi
if promote --allow-candidate && published; then pass "--allow-candidate promotes a candidate"; else fail "--allow-candidate promotes a candidate"; fi

rc_release 0.1.0dev250
if ! promote --allow-candidate && ! published; then pass "a development build is never promoted"; else fail "a development build is never promoted"; fi

rc_release 0.1.0
echo changed >>"$tmp/rc/cuore-0.1.0-1-x86_64.pkg.tar.zst"
if ! promote && ! published; then pass "a changed package stops the promotion"; else fail "a changed package stops the promotion"; fi

((failures == 0)) || exit 1
