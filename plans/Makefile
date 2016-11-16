
VARFILE=../.azure-terraform.json
TERRAFORM=terraform


plan: validate
	$(TERRAFORM) plan --var-file=$(VARFILE) .

validate: 
	$(TERRAFORM) validate --var-file=$(VARFILE) *.tf


.PHONY: validate plan
