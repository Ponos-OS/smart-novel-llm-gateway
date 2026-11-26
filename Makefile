SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

.ONESHELL:
.PHONY: help init start_dev docker_build docker_run docker_run_gpu compose_up compose_up_gpu format format_check lint_check lint clean

IMAGE ?= smart-novel-llm-gateway
TAG   ?= dev

# Tracked and new text files, NUL separated.
TEXT_FILES = git grep --untracked -Ilz -e ''
YAML_FILES = $(TEXT_FILES) -- '*.yml' '*.yaml'
TOML_FILES = $(TEXT_FILES) -- '*.toml'
# The fixers matter for everything else, such as Markdown, YAML, JSON, the Makefile and the Dockerfile.
WHITESPACE_FIXERS = end-of-file-fixer trailing-whitespace-fixer

## Show this help message
help:
	@echo "Makefile targets:"
	@targets="$$(grep -E '^[a-zA-Z_-]+:' $(MAKEFILE_LIST) | cut -d: -f1)"; \
	width="$$(printf '%s\n' "$$targets" | awk '{ if (length > max) max = length } END { print max }')"; \
	awk -v width="$$width" ' \
		/^## / { description = substr($$0, 4); next } \
		/^[a-zA-Z_-]+:/ && description { \
			target = $$1; \
			sub(/:.*/, "", target); \
			printf "  make \033[36m%-*s\033[0m - %s\n", width, target, description; \
			description = ""; \
		} \
	' $(MAKEFILE_LIST)

## Set up the local dev environment
init:
	@command -v uv >/dev/null 2>&1 || { echo "uv is required: https://docs.astral.sh/uv/"; exit 1; }
	npm ci
	uv sync
	npx --no-install lefthook install

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

## Format the code
format:
	$(YAML_FILES) | xargs -0 uv run check-yaml
	$(TOML_FILES) | xargs -0 uv run check-toml
	# A fixer exits 1 after changing a file, so only a second failure is an error.
	for fixer in $(WHITESPACE_FIXERS); do
		$(TEXT_FILES) | xargs -0 uv run $$fixer || $(TEXT_FILES) | xargs -0 uv run $$fixer
	done
	uv run taplo format
	uv run ruff check --fix .
	npx --no-install ast-grep scan -U src tests
	uv run ruff format .

## Check formatting
format_check:
	$(YAML_FILES) | xargs -0 uv run check-yaml
	$(TOML_FILES) | xargs -0 uv run check-toml
	# The fixers have no check mode, so they run on a throwaway copy.
	copy="$$(mktemp -d)"
	trap 'rm -rf "$$copy"' EXIT
	$(TEXT_FILES) | tar --null -T - -cf - | tar -xf - -C "$$copy"
	for fixer in $(WHITESPACE_FIXERS); do
		$(TEXT_FILES) | (cd "$$copy" && xargs -0 uv run --project "$(CURDIR)" $$fixer)
	done
	uv run taplo format --check
	uv run ruff format --check .
	npx --no-install ast-grep scan src tests

## Check linters
lint_check: format_check
	uv run ruff check .
	uv run flake8
	uv run ty check
	uv run lint-imports
	npm run --silent check:duplication

## Apply linters
lint: format
	uv run flake8
	uv run ty check
	uv run lint-imports
	npm run --silent check:duplication

## Remove caches and venv
clean:
	rm -rf .venv .ruff_cache .import_linter_cache
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
