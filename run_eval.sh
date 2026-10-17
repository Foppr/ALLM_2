#!/usr/bin/env bash
# Run one BALROG evaluation.
#
#   ./run_eval.sh <agent.type> <client> <model_id> [extra hydra overrides...]
#
#   client:  ollama   local model via Ollama (starts the server and pulls the model if needed)
#            nim      NVIDIA NIM cloud API     (key: NVIDIA_API_KEY)
#            mistral  Mistral API              (key: MISTRAL_API_KEY)
#            gemini   Google AI Studio         (key: GEMINI_API_KEY)
#
# Examples:
#   ./run_eval.sh naive ollama qwen2.5:7b
#   ./run_eval.sh naive nim openai/gpt-oss-20b
#   ENVS=babyai ./run_eval.sh custom gemini gemini-3.8-flash
#   ./run_eval.sh naive nim openai/gpt-oss-20b eval.num_workers=2     # extra overrides at the end
#
# Optional environment variables:
#   ENVS=babyai-textworld   which environments (default: all six)
#   FULL=1                  BALROG's full default episode counts instead of the reduced budget below
#
# Keep running after logout:  nohup ./run_eval.sh naive ollama qwen2.5:7b > run.log 2>&1 &
# Results go to results/<timestamp>_<agent>_<model>/ inside this folder.
set -uo pipefail

if [[ $# -lt 3 ]]; then sed -n '2,22p' "$0"; exit 1; fi
AGENT="$1"; CLIENT="$2"; MODEL="$3"; shift 3
EXTRA=("$@")

# ---------- settings: edit if your paths differ ----------
BALROG_DIR="$(cd "$(dirname "$0")" && pwd)"          # this script lives in the BALROG folder
VENV="$BALROG_DIR/.venv"
OLLAMA_BIN="$BALROG_DIR/ollama/bin"
export OLLAMA_MODELS="$BALROG_DIR/ollama_models"
KEYS_FILE="$HOME/balrog_keys.env"
ENVS="${ENVS:-babyai-babaisai-textworld-crafter-minihack-nle}"
# Reduced episode budget (BALROG's defaults take days on free tiers). FULL=1 disables it.
BUDGET=(eval.num_episodes.babyai=2 eval.num_episodes.babaisai=1 eval.num_episodes.textworld=2
        eval.num_episodes.crafter=1 eval.num_episodes.minihack=1 eval.num_episodes.nle=1)
# ---------------------------------------------------------

source "$VENV/bin/activate" || { echo "cannot activate $VENV"; exit 1; }
export PATH="$OLLAMA_BIN:$PATH"
[[ -f "$KEYS_FILE" ]] && source "$KEYS_FILE"
cd "$BALROG_DIR"

case "$CLIENT" in
  ollama)
    ARGS=(client.client_name=vllm client.base_url=http://127.0.0.1:11434/v1
          eval.num_workers=1 client.timeout=600 client.generate_kwargs.max_tokens=2048)
    command -v ollama >/dev/null || { echo "ollama not found in $OLLAMA_BIN"; exit 1; }
    if ! curl -s http://127.0.0.1:11434/api/version >/dev/null; then
      echo "starting ollama server (log: $BALROG_DIR/ollama_serve.log)"
      OLLAMA_CONTEXT_LENGTH=16384 setsid nohup ollama serve > "$BALROG_DIR/ollama_serve.log" 2>&1 < /dev/null &
      for _ in $(seq 30); do curl -s http://127.0.0.1:11434/api/version >/dev/null && break; sleep 1; done
    fi
    if ! ollama show "$MODEL" >/dev/null 2>&1; then
      echo "pulling $MODEL"; ollama pull "$MODEL" || exit 1
    fi ;;
  nim|nvidia)
    export OPENAI_API_KEY="${NVIDIA_API_KEY:?NVIDIA_API_KEY not set in $KEYS_FILE}"
    ARGS=(client.client_name=nvidia client.base_url=https://integrate.api.nvidia.com/v1
          eval.num_workers=4 client.max_retries=8 client.delay=4) ;;
  mistral)
    export OPENAI_API_KEY="${MISTRAL_API_KEY:?MISTRAL_API_KEY not set in $KEYS_FILE}"
    ARGS=(client.client_name=nvidia client.base_url=https://api.mistral.ai/v1
          eval.num_workers=1 client.max_retries=8 client.delay=5) ;;
  gemini)
    : "${GEMINI_API_KEY:?GEMINI_API_KEY not set in $KEYS_FILE}"
    ARGS=(client.client_name=gemini eval.num_workers=1 client.max_retries=10 client.delay=10) ;;
  *) echo "unknown client '$CLIENT' (use ollama, nim, mistral or gemini)"; exit 1 ;;
esac
[[ "${FULL:-0}" == "1" ]] && BUDGET=()

# drop a default when you pass the same key yourself (Hydra may reject a key given twice)
DEFAULTS=()
for d in "${ARGS[@]}" "${BUDGET[@]}"; do
  keep=1; for e in "${EXTRA[@]}"; do [[ "${e%%=*}" == "${d%%=*}" ]] && keep=0; done
  [[ $keep == 1 ]] && DEFAULTS+=("$d")
done

echo "[$(date '+%F %T')] START agent=$AGENT client=$CLIENT model=$MODEL envs=$ENVS"
python eval.py agent.type="$AGENT" agent.max_image_history=0 agent.max_text_history=16 \
  envs.names="$ENVS" client.model_id="$MODEL" "${DEFAULTS[@]}" "${EXTRA[@]}"
rc=$?

# eval.py exits 0 even if every API call failed, so check that episodes actually finished
RUN="$(ls -td results/*/ 2>/dev/null | head -1)"
n=$(find "$RUN" -name '*_run_*.json' 2>/dev/null | wc -l)
echo "[$(date '+%F %T')] END (exit $rc): $n finished episodes in $RUN"
[[ $n -eq 0 ]] && echo "WARNING: no episodes finished - check ${RUN}eval.log" && rc=2
exit $rc
