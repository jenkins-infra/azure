SECRETS=.azure-packer.json
PACKER=../scripts/packer

all: check
	for t in $(shell find . -iname "*.json" -type f); do \
		./scripts/packer build --var-file=$(SECRETS) $$t; \
	done;

check: $(SECRETS)
	for t in $(shell find . -iname "*.json" -type f); do \
		$(PACKER) validate --var-file=$(SECRETS) $$t; \
	done;


$(SECRETS):
	echo ">> $(SECRETS) doesn't exist, you'll probably want to generate it yourself"
	ln -sf vars.json $(SECRETS)

clean:


.PHONY: all validate clean validate-yaml
