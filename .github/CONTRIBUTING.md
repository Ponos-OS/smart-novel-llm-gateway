## Quick Start

`make docker_build`, then `make docker_run` or `make docker_run_gpu` (both read `LLM_HF_MODEL` from your environment).

`make compose_up` (or `make compose_up_gpu`) builds from source and starts it using `compose.yaml`, which also shows how to run the published image from another project.

## Release

Pushing to `main` runs `.github/workflows/dockerhub-release.yml`: semantic-release derives the version from conventional commits and pushes `9109679196/smart-novel-llm-gateway:<version>` and `:latest`. Requires the `DOCKERHUB_TOKEN` repository secret.
