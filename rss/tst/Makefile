TESTS = \
    detect.lua \
    extract.lua

.PHONY: all $(TESTS)

all: $(TESTS)
	@echo "all tests passed"

$(TESTS):
	@lua5.4 $@ $(CURDIR)
