SHELL := /bin/bash

# Bumped by hand; `make package VERSION=1.1.0` overrides it for a one-off.
VERSION := 1.0.0

.PHONY: run debug setup build test clean package app reinstall icon

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

# Just the bundle, no disk image.
app:
	@VERSION=$(VERSION) DMG=0 ./scripts/package.sh

# Build the bundle and drop it into /Applications, replacing any copy already
# there. A running OsumTimer is quit first — macOS will not overwrite a live
# bundle cleanly, and the new one has to be the copy that gets relaunched.
reinstall: app
	@osascript -e 'quit app "OsumTimer"' >/dev/null 2>&1 || true
	@rm -rf /Applications/OsumTimer.app
	@cp -R build/OsumTimer.app /Applications/OsumTimer.app
	@echo "installed: /Applications/OsumTimer.app"
	@open -a /Applications/OsumTimer.app

# Just the icon, for looking at it without a full build.
icon:
	@mkdir -p build
	@swift scripts/make-icon.swift build/OsumTimer.icns && echo "build/OsumTimer.icns"

clean:
	swift package clean
	rm -rf build
