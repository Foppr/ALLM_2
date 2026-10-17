#!/usr/bin/env bash
# Runs all env jobs for ONE model one after another (they share one rate limit).
# Finished jobs (state/*.done) are skipped, so re-running resumes where it stopped.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
tag="$1"
mkdir -p "$HERE/state" "$HERE/logs"
for job in "$HERE"/jobs/"${tag}"_*.sh; do
  name="$(basename "$job" .sh)"
  [[ -f "$HERE/state/$name.done" ]] && { echo "skip $name (done)"; continue; }
  rm -f "$HERE/state/$name.failed"
  touch "$HERE/state/$name.running"
  if bash "$job" > "$HERE/logs/$name.log" 2>&1; then
    mv "$HERE/state/$name.running" "$HERE/state/$name.done"
  else
    mv "$HERE/state/$name.running" "$HERE/state/$name.failed"
  fi
done
echo "lane $tag finished at $(date '+%F %T')"
