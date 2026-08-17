CLOUD ?= gcp
TF_DIR := terraform/$(CLOUD)
TFVARS ?= terraform.tfvars

.PHONY: infra-init infra-plan infra-apply outputs kubeconfig fmt validate validate-all

infra-init:
	tofu -chdir=$(TF_DIR) init

infra-plan:
	tofu -chdir=$(TF_DIR) plan -var-file=$(TFVARS) -out=openworkflow.tfplan

infra-apply:
	tofu -chdir=$(TF_DIR) apply openworkflow.tfplan

outputs:
	tofu -chdir=$(TF_DIR) output

kubeconfig:
	./scripts/$(CLOUD)-kubeconfig.sh

fmt:
	tofu fmt -recursive terraform

validate:
	tofu fmt -check -recursive $(TF_DIR)
	tofu -chdir=$(TF_DIR) init -backend=false
	tofu -chdir=$(TF_DIR) validate

validate-all:
	@tofu fmt -check -recursive terraform
	@for cloud in gcp aws azure; do \
		tofu -chdir=terraform/$$cloud init -backend=false && \
		tofu -chdir=terraform/$$cloud validate || exit 1; \
	done
