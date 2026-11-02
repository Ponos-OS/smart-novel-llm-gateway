# llama-server (CPU and CUDA capable) + Qwen3-TTS behind one OpenAI-compatible gateway.
FROM ghcr.io/ggml-org/llama.cpp:server-cuda

ARG TTS_MODEL=Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice
ENV TTS_MODEL=${TTS_MODEL} \
    HF_HOME=/models/huggingface \
    LLAMA_CACHE=/models/llama \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    PATH=/opt/venv/bin:$PATH \
    GATEWAY_PORT=8000

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl libsndfile1 sox && \
    rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

COPY pyproject.toml uv.lock .python-version /app/
RUN uv sync --project /app --frozen --no-dev --no-install-project

RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('${TTS_MODEL}')"

COPY src/server.py /app/server.py
COPY --chmod=755 scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

WORKDIR /app
VOLUME /models
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --retries=10 --start-period=300s CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
