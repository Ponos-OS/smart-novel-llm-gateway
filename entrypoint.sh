#!/bin/sh
set -eu

: "${LLM_HF_MODEL:?Set LLM_HF_MODEL, e.g. unsloth/Qwen3.6-35B-A3B-GGUF:Q4_K_M}"

# 0 keeps everything on CPU; a large value offloads all layers to the GPU.
llama-server \
  -hf "$LLM_HF_MODEL" \
  --host 127.0.0.1 \
  --port 8081 \
  --n-gpu-layers "${LLM_GPU_LAYERS:-0}" \
  --ctx-size "${LLM_CTX_SIZE:-8192}" \
  ${LLM_EXTRA_ARGS:-} &

exec python /app/server.py
