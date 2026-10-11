# aien-receipts

Published verification receipts for the AIEN repositories. This repository holds data only:
no code, no workflows, no secrets. It is the public, append-only shelf that the thin
"AIEN Verification" check on every AIEN repository reads from.

## Layout

```
<repo>/<sha>/bundle.json
```

- `<repo>` is the GitHub repository name under `aien-dev` (for example `omega`,
  `aien-sovereign-core`, `aienos`, `physics`, `aien-protocols`, `aien-architecture`,
  `aegis-runtime`, `spark-rsi`, `benchmarks`).
- `<sha>` is the full 40-character commit hash of the verified commit in that repository.
- `bundle.json` is the signed bundle produced by `aien-test bundle-sign` on the machine that
  ran the gates (the DGX Spark). It carries one receipt per gate for that exact commit, the
  verdict of each gate, and a signature over the whole bundle.

Nothing else lives here. A commit that has not been verified has no directory.

## How a bundle is checked

The consuming repository verifies the bundle with `aien-test verify-bundle`, using

- the repository name and commit under test,
- the public key committed in that repository as `.aien/verify.pub`, read from the base
  branch (never from the commit under test), and
- the always-run gate list `.aien/always` from the same base branch, passed as `--require`.

The signing key never leaves the verification machine. This repository only receives the
signed output, so anyone can read and re-verify a bundle with the public key.

## Rules

- Append only. A bundle for a given `<repo>/<sha>` is published once and never rewritten.
  A new verification of the same commit is a new commit here that must carry the same bytes.
- No workflows run in this repository.
- Published by the AIEN verification pipeline on the DGX Spark; see the `aien-architecture`
  repository for the pipeline doctrine (ADR 0033, manifest v2).

## License

AGPL-3.0-or-later, like every AIEN repository. See `LICENSE`.
