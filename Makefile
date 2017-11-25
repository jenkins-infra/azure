

VARFILE=.azure-terraform.json
TERRAFORM=./scripts/terraform
# Grab our configured prefix from the .azure-terraform.json file
TF_VAR_PREFIX:=$(shell python -c "import json; print json.load(file('.azure-terraform.json'))['prefix']")
# Directory to use for local preparatory state
TFSTATE_PREPARE_DIR=.tf-prepare

check:
	@python -c "import sys; sys.exit(0) if sys.version_info < (3,0) else sys.exit('\n\nPython 2 required \n\n')"

refresh: check init
	$(TERRAFORM) refresh -var-file=$(VARFILE) plans

terraform: check init refresh
	$(TERRAFORM) plan -var-file=$(VARFILE) plans

validate: check init
	$(TERRAFORM) validate --var-file=$(VARFILE) plans

generate: check
	$(MAKE) -C arm_templates

deploy: check init refresh
	$(TERRAFORM) apply -var-file=$(VARFILE) -auto-approve=true plans

init: check prepare generate
	$(TERRAFORM) init \
		-backend-config="storage_account_name=$(TF_VAR_PREFIX)tfstate" \
		-backend-config="container_name=tfstate" \
		-backend-config="key=terraform.tfstate" \
		-backend-config="access_key=$(shell python -c "import json; ms=json.load(file('$(TFSTATE_PREPARE_DIR)/terraform.tfstate'))['modules']; print ms[0]['resources']['azurerm_storage_account.tfstate']['primary']['attributes']['primary_access_key']")" \
		-force-copy \
		plans

clean:
	$(MAKE) -C arm_templates clean
	rm -Rf ${TFSTATE_PREPARE_DIR}
	rm -Rf .terraform/

.PHONY: terraform deploy init clean validate generate prepare

prepare:
	# Before using azure backend, we first have to be sure that 
	# remote_tfstate is correctly configured and we must to do it in an other 
	# directory as the global directory is already configured to use azure backend.
	mkdir $(TFSTATE_PREPARE_DIR) || true
	cd $(TFSTATE_PREPARE_DIR) && ../$(TERRAFORM) init
	cp $(VARFILE) $(TFSTATE_PREPARE_DIR)/$(VARFILE)
	for file in variables provider remote-state; do \
		cp plans/$$file.tf $(TFSTATE_PREPARE_DIR); \
	done;
	cd $(TFSTATE_PREPARE_DIR) && ../$(TERRAFORM) init &&  ../$(TERRAFORM) apply -var-file=$(VARFILE) -auto-approve=true
	sleep 90

