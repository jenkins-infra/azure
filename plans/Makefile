
VARFILE=../.azure-terraform.json
TERRAFORM=terraform


plan: validate
	$(TERRAFORM) plan --var-file=$(VARFILE) .

validate: 
	$(TERRAFORM) validate *.tf

apply: validate
	$(TERRAFORM) apply --var-file=$(VARFILE) .


.PHONY: validate plan apply
