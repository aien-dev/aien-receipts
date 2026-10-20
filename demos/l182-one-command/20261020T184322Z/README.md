# One-command demo, clean folder, 2026-10-20T18:43:22Z

What this is: the full output of the AIEN one-command demo (`run`, the same file served at
https://aienos.com/run) on a fresh folder on an NVIDIA DGX Spark, with nothing reused: Rust installed
inside the folder, sources fetched at pinned commits (tag `demo-l182-v1`), the official
Qwen/Qwen3.8-27B-FP8 weights downloaded and checked file by file, converted to the 4-bit store, one
prompt answered on the GPU by Omega with no CUDA.

| File | What it holds |
|---|---|
| `run` | the exact script that ran (sha256 in `demo-receipt.json`, field `run_sha256`) |
| `run.log` | everything the script printed |
| `demo-receipt.json` | pinned commits, weights revision, GPU, driver, kernel, 4-bit store sha256, linked libraries, step timings |
| `answer.json` | the prompt, the answer, every token id, the chip time of every step, and the speed figures |
| `timings.txt` | seconds per step |
| `gpu-step.*` | a second, separately timed run of the GPU step only (see Timings) |
| `SHA256SUMS` | sha256 of every file here |

## Result

- Answer: three coherent sentences (in `answer.json`).
- 83 tokens in 5.86 s = 14.15 tokens/s wall clock (calc:62fd33ec).
- 13.65 GB of 4-bit weights read per token: 193.2 GB/s, 0.708 of the Spark's 273 GB/s memory limit (calc:8fe79f5c).
- Chip time per token: 70.33 ms median = 14.22 tokens/s while the GPU works.
- Demo program links only libc, libm and libgcc (`linked` field). No libcuda.
- 4-bit store sha256 `2a45c537...8f1a69`, byte-identical to the store converted on 2026-10-19 from the same weights.

## Timings, read honestly

Setup from nothing to the GPU step took 775.2 s, 12.9 minutes (calc:d760348d): check 0.4, Rust 9.6,
sources 11.5, build 138.3, weights 299.6, convert 315.8. The `answer` step shows 11089.2 s because on
this shared machine the script waited about three hours in a queue for the GPU before it could start.
A stock Spark has no such queue. The GPU work itself was 26.6 s to load the model, 2.0 s for the
prompt and 5.9 s to write the answer (fields `open_s`, `prefill_s`, `gen_s` in `answer.json`). 

To time the GPU step without the queue, it was run once more on the same folder at 18:55Z
(`gpu-step.sh`, `gpu-step.log`, `gpu-step-answer.json`): 107.32 s end to end, same answer. That run is a
time bound, not a speed figure: a training job was using the GPU at the same time without the GPU
lock, and chip time per token rose from 70.33 ms to 194.94 ms (2.77x, calc:c9dd2506). Setup plus that
GPU step is 14.71 minutes (calc:3cb838d3).

The machine was busy with other work during the run (load average 51 to 58 at the end), so the
build, download and convert times are slower than an idle Spark would give.

## The test harness

The script ran under `env -i` with HOME inside the folder and no Rust installed for that HOME (this is
why rustup prints a HOME warning at the top of `run.log`). On this shared machine the build and GPU
steps were wrapped in the machine's queue tools (`AIEN_DEMO_BUILD_WRAP`, `AIEN_DEMO_GPU_WRAP`); on a
stock Spark both are empty.
