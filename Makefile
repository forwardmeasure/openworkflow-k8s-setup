SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

TOFU ?= tofu
KUBECTL ?= kubectl
HELMFILE ?= helmfile
GCP_DIR := terraform/gcp
BOOTSTRAP_DIR := bootstrap

.PHONY: help infra-init infra-plan infra-apply kubeconfig environment gateway-api bootstrap bootstrap-diff workload-values validate verify outputs

help:
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "%-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

infra-init: ## Initialize the GCP OpenTofu stack
	$(TOFU) -chdir=$(GCP_DIR) init

infra-plan: ## Plan the GCP infrastructure
	$(TOFU) -chdir=$(GCP_DIR) plan -out=openworkflow.tfplan

infra-apply: ## Apply the previously reviewed GCP plan
	$(TOFU) -chdir=$(GCP_DIR) apply openworkflow.tfplan

kubeconfig: ## Configure kubectl for the provisioned GKE cluster
	./scripts/gke-kubeconfig.sh

environment: ## Generate the non-secret Helmfile environment from Terraform outputs
	./scripts/render-gcp-environment.sh

gateway-api: ## Install the pinned Kubernetes Gateway API standard CRDs
	$(KUBECTL) apply --server-side --force-conflicts -k manifests/gateway-api

bootstrap: environment gateway-api ## Install or update portable platform components
	cd $(BOOTSTRAP_DIR) && $(HELMFILE) -e gcp sync

bootstrap-diff: environment ## Preview platform component changes
	cd $(BOOTSTRAP_DIR) && $(HELMFILE) -e gcp diff

workload-values: ## Generate non-secret overlays for both OpenWorkflow engines
	./scripts/render-workload-values.sh

validate: ## Format-check and validate infrastructure and local Helm chart
	$(TOFU) -chdir=$(GCP_DIR) fmt -check -recursive
	$(TOFU) -chdir=$(GCP_DIR) init -backend=false
	$(TOFU) -chdir=$(GCP_DIR) validate
	helm lint $(BOOTSTRAP_DIR)/charts/openworkflow-platform --values $(BOOTSTRAP_DIR)/environments/gcp.example.yaml
	cd $(BOOTSTRAP_DIR) && $(HELMFILE) -e example template >/dev/null

verify: ## Check cluster, operators, certificate, gateway, identity and Kafka
	./scripts/verify.sh

outputs: ## Print GCP infrastructure and workload contract outputs
	$(TOFU) -chdir=$(GCP_DIR) output
