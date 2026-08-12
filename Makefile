SHELL := /bin/bash

.PHONY: run debug setup build test clean

# Launch the menu bar app in the foreground; Ctrl-C to stop.
run:
	swift run

# One-time install of the tools `debug` needs.
setup:
	@command -v fswatch >/dev/null || brew install fswatch
	@echo "setup ok: $$(fswatch --version | head -1)"

# Like `run`, but watches the sources and restarts the app on any change.
WATCH_PATHS := Sources Package.swift
debug:
	@command -v fswatch >/dev/null || { echo "fswatch missing — run 'make setup'"; exit 1; }
	@echo "Watching $(WATCH_PATHS) — Ctrl-C to stop."
	@BIN=$$(swift build --show-bin-path)/OsumTimer; \
	stop() { [ -n "$$PID" ] && { kill $$PID 2>/dev/null; wait $$PID 2>/dev/null; }; PID=""; }; \
	start() { swift build || return 0; "$$BIN" & PID=$$!; }; \
	trap 'stop; kill $$WATCHER 2>/dev/null; exit 0' INT TERM; \
	start; \
	exec 3< <(fswatch -o -l 0.3 -e '/\.build/' $(WATCH_PATHS)); WATCHER=$$!; \
	while :; do \
		if read -r -t 1 _ <&3; then \
			echo "--- change detected, restarting ---"; \
			stop; start; \
		elif [ $$? -gt 128 ]; then continue; else break; fi; \
	done

build:
	swift build

test:
	swift test

clean:
	swift package clean
