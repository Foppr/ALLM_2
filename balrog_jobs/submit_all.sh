#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
count=0
for job in "$HERE"/slurm_jobs/*.slurm; do
  sbatch "$job"
  count=$((count+1))
  sleep 0.2 # Slight delay to be gentle on the SLURM scheduler
done
echo "Successfully queued $count jobs!"