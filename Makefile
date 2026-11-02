SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

.ONESHELL:
.PHONY: help init start_dev docker_build docker_run docker_run_gpu compose_up compose_up_gpu lint_check lint clean

IMAGE ?= smart-novel-llm-gateway
TAG   ?= dev

## Show this help
help:
	@awk 'BEGIN {FS = ":.*##|## "} /^[a-zA-Z_-]+:.*?## |^## /{if ($$0 ~ /^##/) {print "\n" $$2} else {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}}' $(MAKEFILE_LIST)

## Set up the local dev environment (.venv, deps)
init:
	@command -v uv >/dev/null 2>&1 || { echo "uv is required: https://docs.astral.sh/uv/"; exit 1; }
	uv sync
	uv run pre-commit install || true

## Run the gateway with auto-reload (expects llama-server on 127.0.0.1:8081)
start_dev:
	uv run uvicorn src.server:app --reload --port $${GATEWAY_PORT:-8000}

## Build the Docker image
docker_build:
	docker build -t $(IMAGE):$(TAG) .

## Run the Docker image on CPU (needs LLM_HF_MODEL)
docker_run:
	docker run --rm -p 8000:8000 -v gateway-models:/models -e LLM_HF_MODEL $(IMAGE):$(TAG)

## Run the Docker image on an NVIDIA GPU (needs LLM_HF_MODEL)
docker_run_gpu:
	docker run --rm --gpus all -p 8000:8000 -v gateway-models:/models -e LLM_HF_MODEL -e LLM_GPU_LAYERS=999 $(IMAGE):$(TAG)

## Build from source and start the gateway on CPU via compose
compose_up:
	docker compose up --build

## Build from source and start the gateway on an NVIDIA GPU via compose
compose_up_gpu:
	docker compose --profile gpu up --build gateway-gpu

## Check linters
lint_check:
	uv run ruff check .
	uv run ruff format --check .
	npx --yes jscpd@4.0.5

## Apply linters
lint:
	uv run ruff format .
	uv run ruff check --fix .
	npx --yes jscpd@4.0.5

## Remove caches and venv
clean:
	rm -rf .venv .ruff_cache
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
