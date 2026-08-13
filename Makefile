SHELL := /bin/bash

# Bumped by hand; `make package VERSION=1.1.0` overrides it for a one-off.
VERSION := 1.0.0

.PHONY: run debug setup build test clean package icon

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

# Build OsumTimer.app and a drag-and-drop .dmg under build/.
package:
	@VERSION=$(VERSION) ./scripts/package.sh

# Just the icon, for looking at it without a full build.
icon:
	@mkdir -p build
	@swift scripts/make-icon.swift build/OsumTimer.icns && echo "build/OsumTimer.icns"

clean:
	swift package clean
	rm -rf build
