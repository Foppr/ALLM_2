#!/usr/bin/env bash
# Generates a .slurm file for every model x agent x env combination
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/config.sh"

mkdir -p "$HERE/slurm_jobs" "$HERE/logs"
rm -f "$HERE"/slurm_jobs/*.slurm

n=0
for line in "${MODELS[@]}"; do
  IFS='|' read -r tag client base model keyvar workers extra model_envs <<< "$line"
  if [[ -n "${model_envs:-}" ]]; then read -ra these_envs <<< "$model_envs"; else these_envs=("${ENVS[@]}"); fi

  for agent in "${AGENT_TYPES[@]}"; do
    for env in "${these_envs[@]}"; do
      job="$HERE/slurm_jobs/${tag}_${agent}_${env}.slurm"

      # 1. Budget and Keys
      budget=""
      if [[ "$FULL" != "1" ]]; then
        budget="eval.num_episodes.${env}=${EPISODES[$env]}"
        [[ -n "${MAX_STEPS[$env]}" ]] && budget+=" eval.max_steps_per_episode=${MAX_STEPS[$env]}"
      fi

      key_line=""
      [[ "$keyvar" != "-" && "$client" != "gemini" ]] && key_line="export OPENAI_API_KEY=\"\${$keyvar:?$keyvar not set in \$KEYS_FILE}\""

      # 2. Dynamic SLURM Resource Allocation
      if [[ "$tag" == ollama* ]]; then
        # Local model: Needs a GPU and an isolated Ollama server instance
        slurm_resources="#SBATCH --partition=gpu\n#SBATCH --gpus=1\n#SBATCH --mem=32G"
        setup_backend='export OLLAMA_HOST="127.0.0.1:$((10000 + SLURM_JOB_ID % 50000))"
echo "Starting local Ollama server on $OLLAMA_HOST..."
OLLAMA_CONTEXT_LENGTH=16384 setsid nohup ollama serve > "$HERE/logs/ollama_$SLURM_JOB_ID.log" 2>&1 &
OLLAMA_PID=$!
sleep 10'
        eval_base_arg='client.base_url=http://$OLLAMA_HOST/v1'
        teardown_backend='kill $OLLAMA_PID'
      else
        # Cloud API: Only needs CPU logic
        slurm_resources="#SBATCH --partition=cpu\n#SBATCH --cpus-per-task=4\n#SBATCH --mem=8G"
        setup_backend=""
        eval_base_arg="client.base_url=$base"
        teardown_backend=""
      fi

      # 3. Write the .slurm script
      cat > "$job" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=${tag}_${env}
#SBATCH --output=${HERE}/logs/%x_%j.out
#SBATCH --time=24:00:00
$(echo -e "$slurm_resources")

set -uo pipefail
HERE="${HERE}"
source "\$HERE/config.sh"
[[ -f "\$KEYS_FILE" ]] && source "\$KEYS_FILE"
if [[ -n "\$CONDA_ENV" ]]; then
  source "\$(conda info --base)/etc/profile.d/conda.sh" && conda activate "\$CONDA_ENV"
fi
$key_line

cd "\$BALROG_DIR"
OUT="\$RESULTS_DIR/$tag/$agent/$env"
mkdir -p "\$OUT"

# Start isolated backend if needed
${setup_backend}

echo "[\$(date '+%F %T')] START $tag/$agent/$env"
python eval.py \\
  agent.type=$agent \$AGENT_ARGS \\
  envs.names=$env \\
  client.client_name=$client client.model_id=$model $eval_base_arg \\
  eval.num_workers=$workers eval.output_dir="\$OUT" \\
  $budget $extra
rc=\$?

# Stop local server
${teardown_backend}

echo "[\$(date '+%F %T')] END $tag/$agent/$env (exit \$rc)"
exit \$rc
EOF
      chmod +x "$job"
      n=$((n+1))
    done
  done
done
echo "Wrote $n SLURM job files to $HERE/slurm_jobs/"