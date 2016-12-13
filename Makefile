

VARFILE=.azure-terraform.json
TERRAFORM=./scripts/terraform
# Grab our configured prefix from the .azure-terraform.json file
TF_VAR_PREFIX:=$(shell python -c "import json; print json.load(file('.azure-terraform.json'))['prefix']")
# Directory to use for local preparatory state
TFSTATE_PREPARE_DIR=.tf-prepare
# Indicator to indicate that we should be using remote state now
TFSTATE_REMOTE_STATE=.tf-remote-state-enabled

terraform: init
	$(TERRAFORM) plan --var-file=$(VARFILE) plans

validate: init
	$(TERRAFORM) validate plans/*.tf

deploy: init
	$(TERRAFORM) apply --var-file=$(VARFILE) plans
	$(TERRAFORM) remote push


init: $(TFSTATE_REMOTE_STATE)
	@echo ">> Remote state enabled"
	$(TERRAFORM) remote pull

# Before creating remote state, we need to first prepare our storage container for
# remote state
$(TFSTATE_REMOTE_STATE): $(TFSTATE_PREPARE_DIR)/terraform.tfstate
	@$(TERRAFORM) remote config \
		-backend=azure \
		-backend-config="resource_group=$(TF_VAR_PREFIX)jenkinsinfra-tfstate" \
		-backend-config="storage_account_name=$(TF_VAR_PREFIX)jenkinstfstate" \
		-backend-config="container_name=tfstate" \
		-backend-config="key=terraform.tfstate" \
		-backend-config="access_key=$(shell python -c "import json; ms=json.load(file('.tf-prepare/terraform.tfstate'))['modules']; print ms[0]['resources']['azurerm_storage_account.tfstate']['primary']['attributes']['primary_access_key']")"
	touch $(TFSTATE_REMOTE_STATE)

# It seems, at least as of terraform 0.7.11, that terraform's graph cannot
# self-describe the remote state resources for placing the state into. In order
# to compensate for this, this Make target copies only the necessary .tf files
# into a preparatory direcetory for running an `apply` against.
#
# This should only need to run once per host that's applying terraform plans
$(TFSTATE_PREPARE_DIR)/terraform.tfstate:
	$(TERRAFORM) remote config -disable || true
	mkdir -p $(TFSTATE_PREPARE_DIR)
	for f in provider remote-state variables; do \
		cp plans/$$f.tf $(TFSTATE_PREPARE_DIR) ; \
	done;
	$(TERRAFORM) apply --var-file=$(VARFILE) --state=$(TFSTATE_PREPARE_DIR)/terraform.tfstate $(TFSTATE_PREPARE_DIR)
	# Allow Azure some time to replicate state across regions and register our
	# containers and storage accounts
	sleep 60


clean:
	rm -f $(TFSTATE_REMOTE_STATE)
	@echo "For safety, remove $(TFSTATE_PREPARE_DIR) yourself"

.PHONY: terraform deploy init clean validate
