# aien-receipts

Published verification receipts for the AIEN repositories. When the Spark judge (the verification
pipeline that runs on the project's NVIDIA DGX Spark) checks a commit, it signs the result and
publishes it here, so anyone can read and re-check it. This repository holds data only: no code,
no workflows, no secrets.

Supports [Aienix](https://github.com/aien-dev/aienix), the core tree of AIEN. Every claim the
project makes is meant to resolve to a bundle on this shelf.

**Status (2026-10-18): in use.** The first bundles were published on 2026-10-16, and the Spark
adds new ones as it verifies commits. Repositories with bundles here today:
`aegis-runtime`, `aien-architecture`, `aienos`, `aien-protocols`, `aien-sovereign-core`,
`benchmarks`, `omega` and `physics`. In `aegis-runtime`, `aien-architecture`, `aienos`,
`aien-protocols`, `benchmarks`, `omega`, `physics` and `spark-rsi` the "AIEN Verification" check
is now required before a pull request can merge.

The verdict of record is the Spark's commit status "AIEN Verification (Spark)". A hosted check
run with the similar name "AIEN Verification" only bridges to it: green there means the bridge
ran, not that the commit passed.

## Layout

```
<repo>/<sha>/bundle.json
```

- `<repo>` is the GitHub repository name under `aien-dev`.
- `<sha>` is the full 40-character commit hash of the verified commit in that repository.
- `bundle.json` is the signed bundle produced by `aien-test bundle-sign` on the machine that
  ran the gates (the DGX Spark). It carries one receipt per gate for that exact commit, the
  verdict of each gate, and a signature over the whole bundle.

Bundle directories contain published data; documentation explains how to inspect it.
A commit that has not been verified has no directory.

## How a bundle is checked

The consuming repository verifies the bundle with `aien-test verify-bundle`, using

- the repository name and commit under test,
- the public key committed in that repository as `.aien/verify.pub`, read from the base
  branch (never from the commit under test), and
- the always-run gate list `.aien/always` from the same base branch, passed as `--require`.

The signing key never leaves the verification machine. This repository only receives the
signed output, so anyone can read and re-verify a bundle with the public key.

## How it works / How we built it

The [pipeline design record](https://github.com/aien-dev/aien-architecture/blob/efbba982f5c095e3ae71c057b22faaafc11ed84d/docs/adr/0033-aien-verification-pipeline.md)
identifies the problem: repeated hosted setup and hardware tests that need Spark.
The worker publishes a signed, commit-bound bundle; an independent consumer uses
base-branch trust anchors to check it rather than trusting the candidate's own key
or gate list. The signature authenticates the recorded statement, not the
correctness or sufficiency of the underlying tests.

**[Walk through one immutable real bundle](docs/verify-one-bundle.md)**: exact
source, shelf and verifier pins; base-ref public key and gate list; official
`aien-test verify-bundle` commands; and a disposable tamper/refusal case. It links
the implementation and existing tests. The optional OpenSSL signature-only
exercise was reproduced; the full verifier recipe is explicitly **not yet
reproduced** in the documentation review environment because Cargo is unavailable.
Neither a signature-only check nor a green hosted bridge replaces the Spark verdict.

## Rules

- Append only (a convention: the branch has no protection rule that enforces it). A bundle for a
  given `<repo>/<sha>` is published once and never rewritten.
  A new verification of the same commit is a new commit here that must carry the same bytes.
- No workflows run in this repository.
- Published by the AIEN verification pipeline on the DGX Spark; see the `aien-architecture`
  repository for the pipeline doctrine (ADR 0033, manifest v2).

## License

Apache-2.0. See `LICENSE`.
