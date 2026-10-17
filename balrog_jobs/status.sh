#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/state" 2>/dev/null || { echo "nothing started yet"; exit 0; }
# a job marked running whose lane is dead was interrupted (machine reboot, kill, ...)
for r in *.running; do
  [[ -f "$r" ]] || continue
  tag=${r%%_*}; pidf="lane_$tag.pid"
  if ! { [[ -f "$pidf" ]] && kill -0 "$(cat "$pidf")" 2>/dev/null; }; then mv "$r" "${r%.running}.failed"; fi
done
for s in running done failed; do
  printf "%-8s %2d: " "$s" "$(ls *.$s 2>/dev/null | wc -l)"; ls *.$s 2>/dev/null | sed "s/\.$s//" | tr '\n' ' '; echo
done
total=$(ls "$HERE"/jobs/*.sh | wc -l)
echo "total jobs: $total"
for f in lane_*.pid; do
  [[ -f "$f" ]] || continue
  pid=$(cat "$f"); tag=${f#lane_}; tag=${tag%.pid}
  kill -0 "$pid" 2>/dev/null && echo "lane $tag: alive" || echo "lane $tag: stopped"
done
