TESTS = \
    detect.sh \
    extract.sh

.PHONY: all $(TESTS)

all: $(TESTS)
	@echo "all tests passed"

$(TESTS):
	@bash $@ $(CURDIR)
