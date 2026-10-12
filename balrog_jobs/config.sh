# ============================================================
#  config.sh: edit this file, then run ./make_jobs.sh
# ============================================================

# Path to your BALROG checkout on the university server
BALROG_DIR="$HOME/BALROG"

# Conda env to activate inside every job (leave empty to use whatever python is on PATH)
CONDA_ENV="balrog"

# File with your API keys (see keys.env.example). Keep it out of git!
KEYS_FILE="$HOME/balrog_keys.env"

# Where results go (one subfolder per model/env)
RESULTS_DIR="$BALROG_DIR/results_sweep"

AGENT_TYPE="naive"
AGENT_ARGS="agent.max_image_history=0 agent.max_text_history=16"

# ------------------------------------------------------------
# Models: one line each
#   tag | client_name | base_url | model_id | key variable | num_workers | extra hydra args
#
#   client_name=nvidia sends requests to base_url with OPENAI_API_KEY (works for NIM and Mistral)
#   client_name=vllm   sends requests to base_url with a dummy key (works for Ollama)
# ------------------------------------------------------------
MODELS=(
  "nim|nvidia|https://integrate.api.nvidia.com/v1|openai/gpt-oss-20b|NVIDIA_API_KEY|4|client.max_retries=8 client.delay=4"
  "mistral|nvidia|https://api.mistral.ai/v1|mistral-medium-latest|MISTRAL_API_KEY|2|client.max_retries=8 client.delay=4"
  "gemini38|gemini|-|gemini-3.8-flash|GEMINI_API_KEY|1|client.max_retries=10 client.delay=5"
  "gemini25lite|gemini|-|gemini-2.5-flash-lite|GEMINI_API_KEY|1|client.max_retries=10 client.delay=5"
  "ollama|vllm|http://127.0.0.1:11434/v1|qwen3.5:9b|-|1|client.timeout=600"
)

ENVS=(babyai babaisai textworld crafter nle minihack)

# ------------------------------------------------------------
# Episode budget. BALROG's defaults (babyai 10/task, babaisai 3/task x 40 tasks,
# crafter 10 x 2000 steps, nle 5 x up to 100k steps, ...) are far too much for free
# tiers. These reduced settings are applied unless you set FULL=1.
# Use the SAME settings for every model so results stay comparable.
# ------------------------------------------------------------
FULL=0
declare -A EPISODES=( [babyai]=2 [babaisai]=1 [textworld]=2 [crafter]=1 [nle]=1 [minihack]=1 )
# Step cap per episode (empty = environment default). Capping crafter/nle lowers their scores
# compared with the paper, but keeps runs to hours instead of days.
declare -A MAX_STEPS=( [babyai]="" [babaisai]="" [textworld]="" [crafter]=300 [nle]=300 [minihack]="" )
