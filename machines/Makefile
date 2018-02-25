SECRETS=.azure-packer.json
PACKER=../scripts/packer

export PACKER_IMAGE_RESOURCE_GROUP:=$(PREFIX)jenkinsci-agents
export PACKER_IMAGE_STORAGE_ACCOUNT:=$(PREFIX)jenkinsimgs
export PACKER_IMAGE_LOCATION:=eastus2

all: check
	for t in $(wildcard *.json); do \
		$(PACKER) build --var-file=$(SECRETS) $$t; \
	done;

check: $(SECRETS)
	@echo ">> Using the following environment variables:"
	@printenv | grep -i \^packer
	for t in $(wildcard *.json); do \
		$(PACKER) validate --var-file=$(SECRETS) $$t; \
	done;


$(SECRETS):
	echo ">> $(SECRETS) doesn't exist, you'll probably want to generate it yourself"
	ln -sf vars.json.example $(SECRETS)

clean:


.PHONY: all validate clean validate-yaml
