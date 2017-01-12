

# The default rule will make sure that all yaml files are converted to their
# JSON equivalents
all: $(patsubst %.yaml,%.json, $(wildcard *.yaml))

%.json: %.yaml
	../scripts/python-with-yaml ./scripts/yaml2json arm_templates/$<

clean:
	rm -f *.json

.PHONY: all clean
