SHELL := /bin/bash

.PHONY: run debug setup build test clean

# Launch the menu bar app in the foreground; Ctrl-C to stop.
run:
	swift run

# One-time install of the tools `debug` needs.
setup:
	@command -v fswatch >/dev/null || brew install fswatch
	@echo "setup ok: $$(fswatch --version | head -1)"

# Like `run`, but watches the sources and restarts the app on every change.
debug:
	@command -v fswatch >/dev/null || { echo "fswatch missing — run 'make setup'"; exit 1; }
	@./scripts/watch.sh

build:
	swift build

test:
	swift test

clean:
	swift package clean
