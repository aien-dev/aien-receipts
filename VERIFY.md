# Verify a bundle yourself

This page checks one real bundle from this shelf using only commodity tools: `curl` to fetch,
`jq` to read and re-encode JSON, `sha256sum` and `basenc` (GNU coreutils) for hashes and hex,
and `openssl` for the signature. You do not need to trust or build the project's own verifier
(`aien-test verify-bundle`). The idea comes from Sigstore's "verify a release with openssl"
page: evidence is only legible to strangers if it can be checked with tools they already have.

Every command below was run on 2026-10-19 and the output shown is the real output.
Tested with OpenSSL 3.0.13, jq 1.7, GNU coreutils 9.4. OpenSSL 3.0 or newer is needed
(`pkeyutl -rawin` for Ed25519).

`ssh-keygen -Y verify` cannot check these bundles today: it only verifies SSHSIG signatures,
which sign a wrapper (`SSHSIG`, a namespace, and a hash of the message), while the Spark signs
the message bytes directly. See [Gaps](#gaps).

## What is signed

A bundle is one JSON object written as canonical JSON: keys sorted by byte, no spaces, integers
only, minimal string escapes, no trailing newline. The signature is Ed25519 over the canonical
bytes of the whole object with its `signature` member removed. The public key is 32 bytes in
hex and is committed in the verified repository as `.aien/verify.pub`. The `executor.id` is
`sha256` of those 32 key bytes.

For bundles that contain only strings, booleans, null, arrays and objects (every bundle on
the shelf on 2026-10-19), `jq -cjS` produces exactly these canonical bytes. `jq` stores numbers
as floating point, so a future bundle with large integers would need a different re-encoder.

## Step by step: one real bundle

The bundle: repository `synapse`, commit `7b4529a8ef61c494a26ed2aa1e95a2c4728aabb2`.

### 1. Fetch the bundle, the key and the always-run gate list

The key and the gate list come from the verified repository's base branch, never from the
commit under test and never from the bundle itself.

```sh
mkdir verify && cd verify
REPO=synapse; SHA=7b4529a8ef61c494a26ed2aa1e95a2c4728aabb2
curl -fsS -o bundle.json https://raw.githubusercontent.com/aien-dev/aien-receipts/main/$REPO/$SHA/bundle.json
curl -fsS -o verify.pub  https://raw.githubusercontent.com/aien-dev/$REPO/main/.aien/verify.pub
curl -fsS -o always      https://raw.githubusercontent.com/aien-dev/$REPO/main/.aien/always
sha256sum bundle.json; cat verify.pub; cat always
```

```
bc2a07afbd092bbfbac65fae5ad797e84765e262527e7aac1ccbdcd527faf1e7  bundle.json
01368e0b02dc1113ae7425ad6ab00fdf5aa7dd97e0690745918a52f051d5cf68
# Gates that run on every commit regardless of changed paths (ADR 0033 Decision 12
# allow-list; inventory contract C6). One gate name per line. Read from the base ref.
CRUMB-VERIFY
SYNAPSE-ZERO-DISK-SECRETS
```

### 2. The key in the bundle is the key the repository committed

```sh
jq -r .signature.pubkey bundle.json
tr -d '[:space:]' < verify.pub; echo
[ "$(jq -r .signature.pubkey bundle.json)" = "$(tr -d '[:space:]' < verify.pub)" ] && echo KEY MATCH || echo KEY MISMATCH
```

```
01368e0b02dc1113ae7425ad6ab00fdf5aa7dd97e0690745918a52f051d5cf68
01368e0b02dc1113ae7425ad6ab00fdf5aa7dd97e0690745918a52f051d5cf68
KEY MATCH
```

### 3. `executor.id` is the fingerprint of that key

```sh
tr -d '[:space:]' < verify.pub | tr a-f A-F | basenc --base16 -d | sha256sum
jq -r .executor.id bundle.json
```

```
6cd958cfb4a61afc145e88e9d8d05bb59c6b764ce9713a37dcf76c542f8eaebb  -
6cd958cfb4a61afc145e88e9d8d05bb59c6b764ce9713a37dcf76c542f8eaebb
```

### 4. Rebuild the signed bytes

The published file is already canonical, so re-encoding it gives back the same bytes. The
signed bytes are the same encoding with `signature` removed.

```sh
jq -cjS . bundle.json | cmp - bundle.json && echo CANONICAL
jq -cjS 'del(.signature)' bundle.json > signed.bin
wc -c bundle.json signed.bin
```

```
CANONICAL
2033 bundle.json
1790 signed.bin
3823 total
```

### 5. Turn the hex key and signature into files openssl reads

An Ed25519 public key in DER form is a fixed 12-byte header (`302a300506032b6570032100`)
followed by the 32 key bytes.

```sh
{ printf '302a300506032b6570032100'; tr -d '[:space:]' < verify.pub; } | tr a-f A-F | basenc --base16 -d > pub.der
openssl pkey -pubin -inform DER -in pub.der -out pub.pem
cat pub.pem
jq -j .signature.sig bundle.json | tr a-f A-F | basenc --base16 -d > sig.bin
wc -c sig.bin
```

```
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAATaOCwLcEROudCWtarAP31qn3ZfgaQdFkYpS8FHVz2g=
-----END PUBLIC KEY-----
64 sig.bin
```

### 6. Check the signature

```sh
openssl pkeyutl -verify -pubin -inkey pub.pem -rawin -in signed.bin -sigfile sig.bin; echo "exit $?"
```

```
Signature Verified Successfully
exit 0
```

### 7. Control: one changed word must fail

A check that cannot fail proves nothing. Flip the verdict and verify again with the same
signature.

```sh
jq -cjS 'del(.signature) | .verdict = "FAIL"' bundle.json > tampered.bin
openssl pkeyutl -verify -pubin -inkey pub.pem -rawin -in tampered.bin -sigfile sig.bin; echo "exit $?"
```

```
Signature Verification Failure
exit 1
```

### 8. The bundle is about this repository and this commit

```sh
jq -r '.schema, .repository, .commit' bundle.json
```

```
aien-verification-bundle/1
github.com/aien-dev/synapse
7b4529a8ef61c494a26ed2aa1e95a2c4728aabb2
```

Both must equal what you asked for: `github.com/aien-dev/$REPO` and the full 40-character `$SHA`
that is also the folder name.

### 9. The declared verdict is what the checks give

The rule (ADR 0033 Decision 7): PASS only if every required check ran or came from cache with
verdict PASS; FAIL if any required check is FAIL; otherwise NOT_RUN. Checks with
`required: false` never change the verdict. The project's verifier also treats a PASS with zero
required checks, or with a `plan.verdict` other than PASS, as NOT_RUN.

```sh
jq -r '[.checks[] | select(.required)] as $r
  | (if any($r[]; .verdict=="FAIL") then "FAIL"
     elif all($r[]; (.status=="run" or .status=="cached") and .verdict=="PASS") then "PASS"
     else "NOT_RUN" end) as $v
  | "declared \(.verdict) computed \($v) plan \(.plan.verdict) required \($r|length)"' bundle.json
```

```
declared PASS computed PASS plan PASS required 4
```

### 10. Every always-run gate is present and required

```sh
grep -v '^#' always | grep . | while read -r g; do
  jq -r --arg g "$g" '[.checks[]|select(.gate==$g)] | if length==1 and .[0].required then "present \($g)" else "MISSING \($g)" end' bundle.json
done
```

```
present CRUMB-VERIFY
present SYNAPSE-ZERO-DISK-SECRETS
```

### 11. No member the format does not define

The project's verifier does not do this check today (see [Gaps](#gaps)), so do it yourself.
Any member outside these lists means the bundle carries something nobody has defined.

```sh
jq -r '
def extra($o; $allowed; $where): ($o | keys - $allowed) | map("\($where).\(.)");
  extra(.; ["checks","commit","executor","finished_utc","graph_digest","plan","receipt_id_scheme","repository","schema","signature","started_utc","tree_digest","verdict"]; "")
+ extra(.executor; ["class","id","machine_digest"]; "executor")
+ extra(.signature; ["alg","pubkey","sig"]; "signature")
+ extra(.plan // {}; ["blocked","reason","removed","unmapped","verdict"]; "plan")
+ ([.checks | to_entries[] | extra(.value; ["backend","check_id","exactness","gate","receipt","required","resolution","status","verdict"]; "checks[\(.key)]")] | add // [])
+ ([.checks | to_entries[] | select(.value.resolution) | extra(.value.resolution; ["receipt","resolved_from"]; "checks[\(.key)].resolution")] | add // [])
| if length == 0 then "closed: no unknown members" else "UNKNOWN: \(join(" "))" end' bundle.json
```

```
closed: no unknown members
```

### 12. `tree_digest` names the commit's file tree

`tree_digest` is `sha256` of the commit's 40-character tree id (as text, no newline). Getting
the tree id needs the commit object; `git` is used here only to fetch it.

```sh
git init -q --bare src.git
git -C src.git fetch -q --depth=1 --filter=tree:0 https://github.com/aien-dev/$REPO "$SHA"
git -C src.git cat-file -p "$SHA" | head -1
git -C src.git rev-parse "$SHA^{tree}" | tr -d '\n' | sha256sum
jq -r .tree_digest bundle.json
```

```
tree 594f27046d0adffc43c53e88648ab47c9672e0ae
990ac544f650777bf8b4f25d449f5e1e0c85702317a98cf95a20d33742d73c86  -
990ac544f650777bf8b4f25d449f5e1e0c85702317a98cf95a20d33742d73c86
```

### 13. Was this bundle ever replaced?

The tree on `main` shows only the newest bytes for each commit. History shows every version.

```sh
git clone -q https://github.com/aien-dev/aien-receipts && cd aien-receipts
git log --format='%h %ad' --date=iso -- $REPO/$SHA/bundle.json
```

```
0339230 2026-10-19 11:35:15 -0500
```

One commit, so this bundle was published once. Other bundles were not. The next command lists
every bundle that a later commit modified or deleted, then prints the verdict history of each
one, oldest first.

```sh
git log --format= --diff-filter=MD --name-only -- '*/bundle.json' > rewritten.txt
echo "rewrites $(wc -l < rewritten.txt), bundles $(sort -u rewritten.txt | wc -l)"
sort -u rewritten.txt | while read -r p; do
  for c in $(git log --format=%h -- "$p"); do git show "$c:$p" | jq -r .verdict; done | tac | paste -sd'>' -
done | sort | uniq -c
```

```
rewrites 40, bundles 32
     12 FAIL>FAIL
      2 FAIL>FAIL>FAIL
      1 FAIL>FAIL>FAIL>FAIL
      1 FAIL>FAIL>PASS
      1 FAIL>FAIL>PASS>PASS
      5 FAIL>PASS
      1 FAIL>PASS>PASS
      2 PASS>FAIL
      7 PASS>PASS
```

So on 2026-10-19, 32 bundles had been replaced 40 times in total, and 10 of them changed
verdict: 8 went from FAIL to PASS and 2 from PASS to FAIL. The README's rule that a bundle "is
published once and never rewritten" is not what happens: a commit verified again gets its
bundle overwritten (new `started_utc`, so new bytes), and only history shows the earlier one.

## Check the whole shelf

Steps 2 to 11 in a loop over a clone of this repository, one key per repository. Run it from
inside the clone. It prints one `BAD` line per bundle that fails a step, then a count.

```sh
CLOSED='def extra($o; $allowed; $where): ($o | keys - $allowed) | map("\($where).\(.)");
  extra(.; ["checks","commit","executor","finished_utc","graph_digest","plan","receipt_id_scheme","repository","schema","signature","started_utc","tree_digest","verdict"]; "")
+ extra(.executor; ["class","id","machine_digest"]; "executor")
+ extra(.signature; ["alg","pubkey","sig"]; "signature")
+ extra(.plan // {}; ["blocked","reason","removed","unmapped","verdict"]; "plan")
+ ([.checks | to_entries[] | extra(.value; ["backend","check_id","exactness","gate","receipt","required","resolution","status","verdict"]; "checks[\(.key)]")] | add // [])
+ ([.checks | to_entries[] | select(.value.resolution) | extra(.value.resolution; ["receipt","resolved_from"]; "checks[\(.key)].resolution")] | add // [])
| length'
ALGEBRA='[.checks[] | select(.required)] as $r
| if any($r[]; .verdict=="FAIL") then "FAIL"
  elif all($r[]; (.status=="run" or .status=="cached") and .verdict=="PASS") then "PASS"
  else "NOT_RUN" end'
W=$(mktemp -d); ok=0; bad=0
for repo in $(ls -d */ | tr -d /); do
  curl -fsS -o "$W/$repo.pub" "https://raw.githubusercontent.com/aien-dev/$repo/main/.aien/verify.pub" || { echo "NO KEY $repo"; continue; }
  pub=$(tr -d '[:space:]' < "$W/$repo.pub")
  printf '302a300506032b6570032100%s' "$pub" | tr a-f A-F | basenc --base16 -d > "$W/$repo.der"
  openssl pkey -pubin -inform DER -in "$W/$repo.der" -out "$W/$repo.pem"
  for f in "$repo"/*/bundle.json; do
    sha=$(basename "$(dirname "$f")"); why=""
    jq -cjS . "$f" | cmp -s - "$f" || why="$why not-canonical"
    [ "$(jq -r .signature.pubkey "$f")" = "$pub" ] || why="$why key"
    [ "$(printf %s "$pub" | tr a-f A-F | basenc --base16 -d | sha256sum | cut -c1-64)" = "$(jq -r .executor.id "$f")" ] || why="$why executor"
    [ "$(jq -r .repository "$f")" = "github.com/aien-dev/$repo" ] || why="$why repository"
    [ "$(jq -r .commit "$f")" = "$sha" ] || why="$why commit"
    jq -cjS 'del(.signature)' "$f" > "$W/signed.bin"
    jq -j .signature.sig "$f" | tr a-f A-F | basenc --base16 -d > "$W/sig.bin"
    openssl pkeyutl -verify -pubin -inkey "$W/$repo.pem" -rawin -in "$W/signed.bin" -sigfile "$W/sig.bin" >/dev/null 2>&1 || why="$why signature"
    [ "$(jq -r "$CLOSED" "$f")" = 0 ] || why="$why unknown-member"
    [ "$(jq -r "$ALGEBRA" "$f")" = "$(jq -r .verdict "$f")" ] || why="$why verdict"
    if [ -z "$why" ]; then ok=$((ok+1)); else bad=$((bad+1)); echo "BAD $f:$why"; fi
  done
done
echo "checked $((ok+bad)) bundles: $ok ok, $bad bad"
```

```
checked 442 bundles: 442 ok, 0 bad
```

That run was on this repository at commit `8056606a1e5ffbfd97610aa0811aee13971686c9`
(2026-10-19). The count grows as the Spark publishes.

As a control, the same loop over a folder holding one copy of the step 1 bundle with its
verdict changed to FAIL printed:

```
BAD synapse/7b4529a8ef61c494a26ed2aa1e95a2c4728aabb2/bundle.json: signature verdict
checked 1 bundles: 0 ok, 1 bad
```

The always-run gate list (step 10) and the tree check (step 12) are left out of the loop
because they need one more fetch per commit.

## What a bundle proves

- The holder of the Spark signing key (the key committed as `.aien/verify.pub`) signed exactly
  these bytes. One changed byte fails the check (step 7).
- The signer stated: this repository, this commit, this file tree, these gates, each with this
  status and verdict, and this overall verdict.
- The overall verdict follows from the listed checks by the published rule (step 9), so the
  signer cannot have declared PASS over a failing required check.
- Every gate the repository requires on every commit appears in the bundle as required (step 10).
- No undefined member is present (step 11, your own check).

## What a bundle does not prove

- **That the gates really ran or really passed.** A signature proves who said it, not that it is
  true. The per-check receipts named by `receipt` and `resolution.receipt` live on the Spark
  (`evidence/<repo>/<sha>/`) and are not published, so a stranger cannot open them.
- **When it was signed.** `started_utc` and `finished_utc` come from the signer's own clock.
  Nothing outside the Spark vouches for the time.
- **Which base the change was judged against.** The bundle names the head commit only. The
  gates chosen depend on what changed since the base, and the base is not recorded. The
  example commit above is a merge with two parents; the bundle does not say which one was the
  base.
- **On what machine and toolchain.** `executor.machine_digest` is a hash of a machine
  description (architecture, kernel release, CPU model and count, memory, GB10 present, QEMU
  available) that is not published, so it can be compared between bundles but not read.
  `graph_digest` and `check_id` can only be recomputed with the project's planner.
- **That the key was the right key at the time.** The key is trusted because GitHub serves it
  from the repository's base branch today. The bundle does not say which commit of the base
  branch held the key, and there is no published list of keys with validity dates.
- **That this is the only bundle for the commit.** The shelf rewrites bundles when a commit is
  verified again (step 13). Nothing outside this repository witnesses its history.
- **Anything stronger than SHA-1 about the source.** `commit` and the tree id are git SHA-1
  object ids. `tree_digest` is `sha256` of the SHA-1 tree id text, so it is no stronger than
  SHA-1.

## Gaps

What the sources do that these bundles do not, and the exact `bundle.json` change for each.
These are proposals: the bundle producer and verifier live in `aien-sovereign-core`
(`tools/aien-test`), and changing them is separate work.

| Gap | Source | Today | Exact change |
|---|---|---|---|
| Self-contained signer identity | Sigstore bundle (certificate travels with the signature); SLSA trusted-builder map | `signature` is `{alg, pubkey, sig}`. Trust comes from fetching `.aien/verify.pub` from GitHub at check time. | Add signed top-level `"key_anchor": {"repository": "github.com/aien-dev/<repo>", "path": ".aien/verify.pub", "commit": "<40-hex base commit the key was read from>"}`, and publish `keys/<executor.id>.json` here (`{"pubkey", "valid_from_utc", "valid_until_utc", "revoked"}`) so the shelf alone says which key was valid when. |
| Independent timestamp | Sigstore signed entry timestamp / RFC 3161 timestamp in the bundle | `started_utc`, `finished_utc` are the signer's own clock. | Add `"signature.rfc3161": "<base64 DER TimeStampResp over sha256 of the 64 signature bytes>"` beside `sig` (outside the signed bytes, like Sigstore), checkable with `openssl ts -verify`. Which time-stamping authority to use is a decision for later. |
| Full 40-character base and head SHAs | crater (experiments are defined by a start and an end commit, both full 40-character hashes) | `commit` is the head, 40 hex, enforced. No base at all. | Add signed `"base": {"ref": "refs/heads/main", "commit": "<40 lower-case hex>"}` and reject a bundle whose `base.commit` is not exactly 40 hex. Keep `commit` as the head. |
| Buildinfo kept separate from results | reproducible-builds.org recording page (environment as a separate product, Debian `.buildinfo`) | Environment is folded into the opaque `executor.machine_digest`; the machine description, toolchain and captured environment are not published. | Publish `<repo>/<sha>/buildinfo.json` (the canonical machine object, the verifier binary's `sha256`, `rustc` version, GPU driver version, captured environment) and add signed `"buildinfo_digest": "<sha256 of canonical buildinfo.json>"`. `executor.machine_digest` must equal `sha256` of `buildinfo.json`'s `machine` member, checkable with `jq -cjS .machine buildinfo.json \| sha256sum`. |
| Unknown-parameter rejection | SLSA verifying-artifacts ("any unrecognized externalParameters SHOULD cause verification to fail") | `aien-test verify-bundle` reads the members it knows and ignores the rest. A bundle with extra members `extra_param`, `executor.surprise` and `checks[0].knob`, signed with a throwaway key, verified as PASS. `plan` is optional: a bundle without it also verified as PASS. | Bump to `"schema": "aien-verification-bundle/2"`, whose rule is: the member lists in step 11 are closed and `plan` is required; any other member is a rejection with a code. No new field. |
| Append-only witness | Rekor (append-only log, monitors, independent witnesses cosigning the tree head) | Append-only is a convention. 40 rewrites of 32 bundle paths on 2026-10-19, 10 with a changed verdict. | Add signed `"supersedes": "<sha256 of the canonical bytes of the earlier bundle for this commit, or null>"` so a re-verification links to what it replaces instead of silently overwriting it, and publish a signed checkpoint `checkpoints/<utc>.json` (`{"receipts_commit": "<40-hex>", "bundles": <count>, "signature": {...}}`) on a schedule for a second key to cosign. |
| Signature independent of JSON parsing | in-toto envelope (DSSE): verify before parsing, no canonicalization dependence, multiple signatures | Checking needs `jq` to re-encode the JSON before the signature can be checked, and there is room for one signature. | Wrap as `{"payloadType": "application/vnd.aien.bundle+json", "payload": "<base64 canonical bytes>", "signatures": [{"keyid": "<executor.id>", "sig": "<hex>"}]}` so the signed bytes are the decoded payload, and a merge desk or witness can add a second signature. |
| `ssh-keygen -Y` verification | Common practice for git and file signing | Not possible: the Spark signs raw bytes, and `ssh-keygen -Y verify` only accepts SSHSIG signatures. | Optional extra member `"signature.sshsig": "<armored SSHSIG over the signed bytes, namespace aien-bundle>"`, verifiable with `ssh-keygen -Y verify -f allowed_signers -I spark -n aien-bundle -s sig < signed.bin`. |
