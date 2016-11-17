

terraform:
	$(MAKE) -C plans

deploy: terraform
	$(MAKE) -C plans apply

.PHONY: terraform deploy
