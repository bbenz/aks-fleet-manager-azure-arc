# ==============================================================================
# Fleet Manager + Arc Multicloud Demo
#
# Thin wrapper around scripts/*.ps1. All real logic lives in PowerShell so it
# behaves identically whether invoked via `make` (if installed) or directly
# via `pwsh`/`powershell`. Every target is safe to re-run. Scripts only
# require PowerShell 5.1 (the version built into every Windows machine), so
# `make` is optional and PowerShell 7+ (`pwsh`) is a nice-to-have, not
# required. If you only have Windows PowerShell, override PWSH:
#   make PWSH="powershell -NoProfile -ExecutionPolicy Bypass -File" plan
# ==============================================================================
SHELL := pwsh
.SHELLFLAGS := -NoProfile -ExecutionPolicy Bypass -Command
PWSH ?= pwsh -NoProfile -ExecutionPolicy Bypass -File

.PHONY: help check-tools bootstrap-auth test-access select-regions plan apply \
        connect-arc join-fleet deploy-workload validate destroy fmt lint \
        secret-scan all

help: ## Show this help
	@echo "Common targets:"
	@echo "  make check-tools      - verify local CLI tool versions"
	@echo "  make bootstrap-auth   - read .env and establish cloud CLI auth"
	@echo "  make test-access      - non-destructive preflight for all 3 clouds"
	@echo "  make select-regions   - discover regions/zones for all 3 clouds"
	@echo "  make plan             - terraform init/validate/plan (saved plans)"
	@echo "  make apply            - apply saved Terraform plans (azure, aws, gcp)"
	@echo "  make connect-arc      - Arc-connect EKS and GKE"
	@echo "  make join-fleet       - join all 3 clusters to Fleet with labels"
	@echo "  make deploy-workload  - apply base app + Fleet placement + overrides"
	@echo "  make validate         - run full demo validation and reports"
	@echo "  make destroy          - tear down everything (reverse order)"
	@echo "  make fmt              - terraform fmt -recursive"
	@echo "  make lint             - terraform validate + tflint (if installed)"
	@echo "  make secret-scan      - scan repo for accidentally committed secrets"
	@echo "  make all              - run the full sequence 00 -> 08"

check-tools: ## Verify local tool versions
	$(PWSH) scripts/00-check-tools.ps1

bootstrap-auth: ## Read .env and establish cloud CLI auth
	$(PWSH) scripts/00-bootstrap-auth.ps1

test-access: ## Non-destructive preflight for Azure/AWS/GCP
	$(PWSH) scripts/01-test-cloud-access.ps1

select-regions: ## Discover regions/zones for all 3 clouds
	$(PWSH) scripts/02-select-regions.ps1

plan: ## terraform init/validate/plan for all roots
	$(PWSH) scripts/03-init-plan.ps1

apply: ## Apply saved Terraform plans
	$(PWSH) scripts/04-apply.ps1

connect-arc: ## Arc-connect EKS and GKE
	$(PWSH) scripts/05-connect-arc.ps1

join-fleet: ## Join all 3 clusters to Fleet with labels
	$(PWSH) scripts/06-join-fleet.ps1

deploy-workload: ## Apply base app + Fleet placement + overrides
	$(PWSH) scripts/07-deploy-workload.ps1

validate: ## Run full demo validation and reports
	$(PWSH) scripts/08-validate-demo.ps1

destroy: ## Tear down everything created by this demo
	$(PWSH) scripts/99-destroy-all.ps1

fmt: ## terraform fmt -recursive on all roots
	terraform fmt -recursive terraform/

lint: ## terraform validate on all roots (+ tflint if present)
	$(PWSH) scripts/lib/lint-all.ps1

secret-scan: ## Scan repo for accidentally committed secrets
	$(PWSH) scripts/lib/secret-scan.ps1

all: check-tools bootstrap-auth test-access select-regions plan apply connect-arc join-fleet deploy-workload validate ## Full sequence
