curl -fsSL https://ollama.com/install.sh | sh

OLLAMA_CONTEXT_LENGTH=16384 ollama serve &
ollama pull qwen3.5:9b
python eval.py agent.type=naive envs.names=babyai \
  client.client_name=vllm client.base_url=http://localhost:11434/v1 \
  client.model_id=qwen3.5:9b eval.num_workers=1