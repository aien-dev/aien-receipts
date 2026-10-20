#!/bin/sh
# L182: time only the GPU step, measured after the shared GPU lock is held (a stock Spark has no lock).
D=/home/drakestapleton/workspace/l182-final/aien-demo
exec /home/drakestapleton/.local/bin/quiet-measure flock /tmp/aien-gb10.lock env AIEN_GB10_LOCK_HELD=1 \
  /usr/bin/time -f "ANSWER_STEP wall %e s" "$D/target/release/qwen38_say" "$D/weights/qwen3.8-27b-fp8" \
  "In three sentences: why does memory bandwidth decide how fast a language model writes?" --gen 128 --receipt "$D/answer2.json"
