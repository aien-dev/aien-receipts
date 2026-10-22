# Verify one published bundle

At receipts commit `f0840f787cf284d985d9a2f76a79dce340cf34be`, I selected [`synapse/7b4529a8ef61c494a26ed2aa1e95a2c4728aabb2/bundle.json`](../synapse/7b4529a8ef61c494a26ed2aa1e95a2c4728aabb2/bundle.json). The bundle says `PASS` for that exact commit. A signature authenticates that statement; it does not prove the underlying gates actually ran. The signer key and always-run gate list belong to the verified repository's base branch, not to this shelf or the untrusted head. I pinned the source branch at `aien-dev/synapse` main `5b732e5d353bbcc3f6d0cd1eac60f2e543601521` for this lesson.

This repository holds data, not verifier code. [`aien-test verify-bundle`](https://github.com/aien-dev/aien-sovereign-core-mv/tree/main/tools/aien-test) is the project verifier. The existing [`VERIFY.md`](../VERIFY.md), recovered from branch `receipts/plain-verify`, teaches the independent OpenSSL route, its JSON canonicalization limit, verdict algebra and tree check. The signed object excludes its `signature` member; Ed25519 verifies the canonical bytes. The public key committed in the base branch is a trust input. A hosted bridge check means the bridge ran; the Spark commit status is the verdict of record. The shelf's append-only rule is a convention, not an enforced branch protection guarantee.

## Fresh checkout exercise

Prerequisites: Git, `curl`, `jq`, `xxd`, OpenSSL 3, and a network connection for the pinned base key and gate list. Checkout receipts commit `f0840f787cf284d985d9a2f76a79dce340cf34be` and run from its root. The commands write only in a temporary directory; the published bundle is never changed.

```sh
set -eu
B=synapse/7b4529a8ef61c494a26ed2aa1e95a2c4728aabb2/bundle.json
S=5b732e5d353bbcc3f6d0cd1eac60f2e543601521
T=$(mktemp -d)
curl -fsS "https://raw.githubusercontent.com/aien-dev/synapse/$S/.aien/verify.pub" -o "$T/key"
curl -fsS "https://raw.githubusercontent.com/aien-dev/synapse/$S/.aien/always" -o "$T/always"
test "$(tr -d '[:space:]' < "$T/key")" = "$(jq -r '.signature.pubkey' "$B")"
while IFS= read -r gate; do
  case "$gate" in ''|\#*) continue;; esac
  jq -e --arg gate "$gate" '.checks | any(.gate == $gate and .required == true and .verdict == "PASS")' "$B" >/dev/null
done < "$T/always"
jq -cjS 'del(.signature)' "$B" > "$T/signed"
{ printf '302a300506032b6570032100'; tr -d '[:space:]' < "$T/key"; } | xxd -r -p > "$T/pub.der"
openssl pkey -pubin -inform DER -in "$T/pub.der" -out "$T/pub.pem"
jq -r '.signature.sig' "$B" | xxd -r -p > "$T/sig"
openssl pkeyutl -verify -pubin -inkey "$T/pub.pem" -rawin -in "$T/signed" -sigfile "$T/sig"
jq -cjS 'del(.signature) | .verdict="FAIL"' "$B" > "$T/tampered"
if openssl pkeyutl -verify -pubin -inkey "$T/pub.pem" -rawin -in "$T/tampered" -sigfile "$T/sig"; then exit 1; else echo 'TAMPER REFUSED'; fi
```

Expected: `Signature Verified Successfully`, then an OpenSSL verification failure and `TAMPER REFUSED`; overall exit 0. The key comparison and required gates are checked, but this bounded exercise is not a full `aien-test` policy replay. The independent walkthrough explains the additional checks. Never change the published source bundle to demonstrate tampering. [Raw replay receipt](teaching-replay-2026-10-22.txt).
