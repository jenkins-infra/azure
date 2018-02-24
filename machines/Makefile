SECRETS=.azure-packer.json
PACKER=../scripts/packer

export PACKER_IMAGE_RESOURCE_GROUP:=$(PREFIX)jenkinsci
export PACKER_IMAGE_STORAGE_ACCOUNT:=$(PREFIX)jenkinsimgs

all: check
	for t in $(shell find . -iname "*.json" -type f); do \
		./scripts/packer build --var-file=$(SECRETS) $$t; \
	done;

check: $(SECRETS)
	@echo ">> Using the following environment variables:"
	@printenv | grep -i \^packer
	for t in $(shell find . -iname "*.json" -type f); do \
		$(PACKER) validate --var-file=$(SECRETS) $$t; \
	done;


$(SECRETS):
	echo ">> $(SECRETS) doesn't exist, you'll probably want to generate it yourself"
	ln -sf vars.json.example $(SECRETS)

clean:


.PHONY: all validate clean validate-yaml
