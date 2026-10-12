#!/usr/bin/env bash
# THE one command: starts one background "lane" per model (5 in parallel);
# each lane runs its 6 env jobs in sequence. Survives logout (setsid + nohup).
#   ./run_all.sh            # all models
#   ./run_all.sh nim ollama # only some models
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/config.sh"
mkdir -p "$HERE/logs" "$HERE/state"
[[ -d "$HERE/jobs" ]] && compgen -G "$HERE/jobs/*.sh" > /dev/null || "$HERE/make_jobs.sh"

if [[ $# -gt 0 ]]; then tags=("$@"); else
  tags=(); for line in "${MODELS[@]}"; do tags+=("${line%%|*}"); done
fi

for tag in "${tags[@]}"; do
  if [[ "$tag" == "ollama" ]] && ! curl -s http://127.0.0.1:11434/api/version > /dev/null; then
    if command -v ollama > /dev/null; then
      echo "starting ollama serve"
      OLLAMA_CONTEXT_LENGTH=16384 setsid nohup ollama serve > "$HERE/logs/ollama_serve.log" 2>&1 < /dev/null &
      sleep 5
    else
      echo "WARNING: ollama not installed/running, skipping ollama lane"; continue
    fi
  fi
  setsid nohup nice -n 10 bash "$HERE/run_lane.sh" "$tag" > "$HERE/logs/lane_$tag.log" 2>&1 < /dev/null &
  echo $! > "$HERE/state/lane_$tag.pid"
  echo "started lane $tag (pid $!)"
done
echo "Check progress with ./status.sh. Stop with ./stop_all.sh"
