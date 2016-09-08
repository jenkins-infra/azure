
PACKER=packer

all: validate

validate:
	$(PACKER) validate -var-file=.azure-packer.json *.json

build: validate
	$(PACKER) build -var-file=.azure-packer.json *.json

PHONY: all validate
