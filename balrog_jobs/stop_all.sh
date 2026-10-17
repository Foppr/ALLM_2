#!/usr/bin/env bash
# Kills every lane and its eval.py processes (each lane is its own process group via setsid)
HERE="$(cd "$(dirname "$0")" && pwd)"
for f in "$HERE"/state/lane_*.pid; do
  [[ -f "$f" ]] || continue
  pid=$(cat "$f")
  kill -TERM -- "-$pid" 2>/dev/null && echo "stopped lane $(basename "$f" .pid)"
  rm -f "$f"
done
# jobs that were mid-run are marked failed so they re-run next time
for r in "$HERE"/state/*.running; do [[ -f "$r" ]] && mv "$r" "${r%.running}.failed"; done
echo "(ollama serve, if started, is left running: pkill -u \$USER ollama to stop it)"
