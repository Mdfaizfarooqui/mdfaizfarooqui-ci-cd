SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
export PATH := $(CURDIR)/.tools/bin:$(PATH)

BUILD_ID ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo local)
GIT_SHA ?= $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
BUILD_DATE ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
BUILD_REPOSITORY ?= local/nginx-nomad-pipeline
IMAGE ?= nginx-nomad-pipeline:$(BUILD_ID)

export BUILD_ID GIT_SHA BUILD_DATE BUILD_REPOSITORY IMAGE

.PHONY: help build test lint fmt validate deploy smoke local-up local-down logs clean install-nomad

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install-nomad: ## Install pinned Nomad into .tools/bin (checksum verified)
	./scripts/install-nomad.sh

build: ## Build the image with BUILD_ID/GIT_SHA/BUILD_DATE baked in
	./scripts/build.sh

test: build ## Build and smoke-test the image locally
	./scripts/test-image.sh

lint: ## Lint Dockerfile, shell scripts and (if installed) Nomad HCL
	@if command -v hadolint >/dev/null 2>&1; then hadolint app/Dockerfile; else echo "hadolint not installed; skipping"; fi
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck -x scripts/*.sh; else echo "shellcheck not installed; skipping"; fi
	@if command -v nomad >/dev/null 2>&1; then nomad fmt -check -recursive nomad/; else echo "nomad not installed; skipping HCL format check"; fi

fmt: ## Format Nomad HCL files
	nomad fmt -recursive nomad/

validate: ## Validate the NGINX job against the configured Nomad cluster
	nomad job validate nomad/nginx.nomad.hcl

deploy: ## Deploy/update NGINX on the configured Nomad cluster
	./scripts/deploy.sh

smoke: ## Smoke-test the running application
	./scripts/smoke-test.sh

local-up: ## Start local Nomad + Loki/Promtail/Grafana + NGINX
	./scripts/local-up.sh

local-down: ## Stop the local stack
	./scripts/local-down.sh

logs: ## Tail NGINX task logs from Nomad
	nomad job logs -f nginx

clean: ## Remove local tools and transient files
	rm -rf .tools .nomad .nomad-dev.log .nomad-dev.pid
