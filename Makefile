CLOUD ?= gcp
TF_DIR := terraform/$(CLOUD)
TFVARS ?= terraform.tfvars

.PHONY: infra-init infra-plan infra-apply infra-destroy-plan infra-destroy uninstall outputs kubeconfig fmt validate test test-all validate-all

infra-init:
	tofu -chdir=$(TF_DIR) init

infra-plan:
	tofu -chdir=$(TF_DIR) plan -var-file=$(TFVARS) -out=openworkflow.tfplan

# Depends on infra-plan so a stale plan can never be applied - apply always
# reflects the current config/tfvars at the moment it's run.
#
# -var-file is repeated here even though it doesn't change the outcome (the
# plan file is self-contained) - `apply <planfile>` still validates that
# whatever variable sources are live at apply time (CLI flags, TF_VAR_*
# env vars, auto-loaded tfvars) agree with what's recorded in the plan, and
# errors on any mismatch rather than just trusting the saved plan. Passing
# the exact same flags used at plan time is the robust way to guarantee
# that, regardless of what's sitting in the shell's environment.
infra-apply: infra-plan
	tofu -chdir=$(TF_DIR) apply -var-file=$(TFVARS) openworkflow.tfplan

# Mirrors infra-plan/infra-apply's plan-file-then-apply shape for destroys,
# using its own plan file (openworkflow-destroy.tfplan, never
# openworkflow.tfplan) so a leftover destroy plan can never accidentally get
# applied by a later `make infra-apply`.
#
# Clears deletion protection before planning, not just before applying -
# Terraform's destroy-safety guard blocks `plan -destroy` too, not only
# `apply`, so this has to happen first regardless of which of the two steps
# is run. Overrides deletion_protection=false at the CLI so this doesn't
# depend on whatever terraform.tfvars currently says - the point of this
# target is to always be able to destroy on request.
#
# Two separate deletion-protection mechanisms, cleared two different ways:
#   - GKE cluster: deletion_protection is a Terraform-provider-side-only
#     guard (confirmed empirically - no corresponding `gcloud` flag exists
#     at all). The -var override below is sufficient on its own.
#   - Cloud SQL: deletion_protection is a real GCP API-level field, and
#     Terraform's own destroy-safety check reads its *cached* state, not
#     live GCP - so an out-of-band gcloud patch alone isn't enough, and
#     neither is a -var override alone. Both the patch AND a -refresh-only
#     apply are needed to get Terraform's state to agree the instance is
#     safe to destroy. This is the exact sequence that was missing before.
infra-destroy-plan:
	@echo "Planning destroy of all Terraform-managed infrastructure for CLOUD=$(CLOUD) (TFVARS=$(TFVARS))"
ifeq ($(CLOUD),gcp)
	@cluster=$$(tofu -chdir=$(TF_DIR) output -raw cluster_name 2>/dev/null || true); \
	project=$$(tofu -chdir=$(TF_DIR) output -raw project_id 2>/dev/null || true); \
	if [ -n "$$cluster" ] && [ -n "$$project" ]; then \
		instance="$${cluster}-postgres"; \
		echo "Clearing live Cloud SQL deletion protection on $$instance (project $$project)..."; \
		gcloud sql instances patch "$$instance" --project="$$project" --no-deletion-protection --quiet || true; \
	else \
		echo "Skipping Cloud SQL deletion-protection clear (cluster_name/project_id not available in state - Cloud SQL instance already destroyed or not yet applied)"; \
	fi
endif
	tofu -chdir=$(TF_DIR) apply -refresh-only -var-file=$(TFVARS) -var deletion_protection=false -auto-approve
	tofu -chdir=$(TF_DIR) plan -destroy -var-file=$(TFVARS) -var deletion_protection=false -out=openworkflow-destroy.tfplan

# Depends on infra-destroy-plan, mirroring infra-apply: infra-plan.
# Same reasoning as infra-apply's -var-file above: `apply <planfile>` still
# validates live variable sources against what's recorded in the plan, so
# repeat the exact flags used at plan time (confirmed necessary - this is
# the fix for the "Mismatch between input and plan variable value" error
# hit when the apply step omitted them).
infra-destroy: infra-destroy-plan
	tofu -chdir=$(TF_DIR) apply -var-file=$(TFVARS) -var deletion_protection=false openworkflow-destroy.tfplan

uninstall: infra-destroy

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

test:
	tofu -chdir=$(TF_DIR) init -backend=false
	tofu -chdir=$(TF_DIR) test

test-all:
	@for cloud in gcp aws azure; do \
		$(MAKE) CLOUD=$$cloud test || exit 1; \
	done

validate-all:
	@tofu fmt -check -recursive terraform
	@for cloud in gcp aws azure; do \
		tofu -chdir=terraform/$$cloud init -backend=false && \
		tofu -chdir=terraform/$$cloud validate || exit 1; \
	done
