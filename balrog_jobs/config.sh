# ============================================================
#  config.sh: edit this file, then run ./make_jobs.sh
# ============================================================

# Comment out or delete the old .venv line:
# source ../.venv/bin/activate

export PATH="$HOME/ollama/bin:$PATH"
export OLLAMA_MODELS="$HOME/ollama_models"
BALROG_DIR="$HOME/ALLM_2"

# Conda env to activate inside every job (leave empty to use whatever python is on PATH)
CONDA_ENV="/zfsstore/user/s2995387/miniforge3/envs/balrog"

# File with your API keys (see keys.env.example). Keep it out of git!
KEYS_FILE="$HOME/balrog_keys.env"

# Where results go (one subfolder per model/env)
RESULTS_DIR="$BALROG_DIR/results_sweep_2"

# ADD SEED
AGENT_ARGS="agent.max_image_history=0 agent.max_text_history=8 envs.env_kwargs.seed=42"

# ------------------------------------------------------------
# Models: one line each
#   tag | client_name | base_url | model_id | key variable | num_workers | extra hydra args
#
#   client_name=nvidia sends requests to base_url with OPENAI_API_KEY (works for NIM and Mistral)
#   client_name=vllm   sends requests to base_url with a dummy key (works for Ollama)
# ------------------------------------------------------------
MODELS=(
"nim|nvidia|https://integrate.api.nvidia.com/v1|openai/gpt-oss-20b|NVIDIA_API_KEY|4|client.max_retries=8 client.delay=4"
"ollamaqwen7b|vllm|http://127.0.0.1:11434/v1|qwen2.5:7b|-|1|client.timeout=600 client.generate_kwargs.max_tokens=1024"
"ollamaqwen32b|vllm|http://127.0.0.1:11434/v1|qwen2.5:32b|-|1|client.timeout=600 client.generate_kwargs.max_tokens=1024"
)

ENVS=(babyai babaisai textworld crafter)  # NO NLE OR MINIHACK
AGENT_TYPES=("naive" "custom_simple_ltsbs" "custom_selfconsistency_detect_cycles" "custom_tree_of_thoughts"  "reAct")  # 3 AGENTS


# ------------------------------------------------------------
# Episode budget. BALROG's defaults (babyai 10/task, babaisai 3/task x 40 tasks,
# crafter 10 x 2000 steps, nle 5 x up to 100k steps, ...) are far too much for free
# tiers. These reduced settings are applied unless you set FULL=1.
# Use the SAME settings for every model so results stay comparable.
# ------------------------------------------------------------
FULL=0
declare -A EPISODES=( [babyai]=1 [babaisai]=1 [textworld]=1 [crafter]=1)
# Step cap per episode (empty = environment default). Capping crafter/nle lowers their scores
# compared with the paper, but keeps runs to hours instead of days.
declare -A MAX_STEPS=( [babyai]=60 [babaisai]=80 [textworld]=80 [crafter]=2000)
