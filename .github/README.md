# smart-novel-llm-gateway

One Docker image exposing an OpenAI-compatible API for smart-novel, replacing Ollama and the local TTS shim:

- `POST /v1/chat/completions` is proxied to the local llama-server (schema-constrained decoding happens there when `response_format` is a JSON schema).
- `POST /v1/audio/speech` is served by Qwen3-TTS (MP3 only).

The same image runs on CPU and NVIDIA GPUs.

## Run

`make docker_build`, then `make docker_run` or `make docker_run_gpu` (both read `LLM_HF_MODEL` from your environment). Or directly:

```bash
# CPU
docker run -p 8000:8000 \
  -v gateway-models:/models \
  -e LLM_HF_MODEL=unsloth/Qwen3.6-35B-A3B-GGUF:Q4_K_M \
  9109679196/smart-novel-llm-gateway

# GPU
docker run --gpus all \
  -p 8000:8000 \
  -v gateway-models:/models \
  -e LLM_HF_MODEL=unsloth/Qwen3.6-35B-A3B-GGUF:Q4_K_M \
  -e LLM_GPU_LAYERS=999 \
  9109679196/smart-novel-llm-gateway
```

The LLM is downloaded on first start into `/models`; mount a volume to keep it. The 4-bit quant of the default model needs about 23 GB of RAM.

`make compose_up` (or `make compose_up_gpu`) builds from source and starts it using `compose.yaml`, which also shows how to run the published image from another project.

## Configuration

| Variable         | Default | Purpose                                                    |
| ---------------- | ------- | ---------------------------------------------------------- |
| `LLM_HF_MODEL`   | none    | Required. `<hf repo>:<quant>` passed to `llama-server -hf` |
| `LLM_GPU_LAYERS` | `0`     | Layers offloaded to the GPU                                |
| `LLM_CTX_SIZE`   | `8192`  | Context size                                               |
| `LLM_EXTRA_ARGS` | empty   | Extra `llama-server` flags                                 |
| `GATEWAY_PORT`   | `8000`  | Public port                                                |

## Release

Pushing to `main` runs `.github/workflows/dockerhub-release.yml`: semantic-release derives the version from conventional commits and pushes `9109679196/smart-novel-llm-gateway:<version>` and `:latest`. Requires the `DOCKERHUB_TOKEN` repository secret.
