BINARY_NAME := CheAppleNotesMCP

FALLBACK_FLAGS := $(shell swift build 2>&1 | grep -q "SendingRisksDataRace" && echo "-Xswiftc -swift-version -Xswiftc 5")

.PHONY: build release install clean test test-unit test-e2e

build:
	swift build $(FALLBACK_FLAGS)

release:
	swift build -c release $(FALLBACK_FLAGS)

install: release
	cp .build/release/$(BINARY_NAME) ~/bin/$(BINARY_NAME)
	chmod +x ~/bin/$(BINARY_NAME)
	codesign --force --sign - ~/bin/$(BINARY_NAME)
	@echo "Installed: ~/bin/$(BINARY_NAME)"

test:
	swift test $(FALLBACK_FLAGS)

# Unit tests only — safe for CI (no Notes.app, no Automation permission).
test-unit:
	swift test $(FALLBACK_FLAGS) --filter CheAppleNotesMCPTests

# E2E tests — requires Notes.app, Full Disk Access, and Automation permission
# for the debug binary. Run `make build` implicitly so the subprocess target
# is up to date, then probe FDA via grant-debug-fda.sh (non-blocking: the
# script exits 1 if FDA missing, prints instructions, and we continue so
# AS-fallback tests still run).
test-e2e: build
	@./scripts/grant-debug-fda.sh || true
	swift test $(FALLBACK_FLAGS) --filter CheAppleNotesMCPE2ETests

clean:
	swift package clean
