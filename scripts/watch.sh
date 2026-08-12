#!/bin/bash
# Build + run OsumTimer, restarting it whenever a watched source file changes.
# Used by `make debug`. Ctrl-C stops both the app and the watcher.
set -u

# One watcher at a time. Two would each run their own copy of the app — which
# looks like duplicate menu bar items — and would fight over the .build lock.
if pgrep -f 'bash .*scripts/watch.sh' | grep -qv "^$$\$"; then
	echo "make debug is already running (pid $(pgrep -f 'bash .*scripts/watch.sh' | grep -v "^$$\$" | tr '\n' ' '))." >&2
	echo "Stop it first, or run: pkill -f scripts/watch.sh" >&2
	exit 1
fi

WATCH_PATHS=("Sources" "Package.swift")
# Seconds of quiet required after a change before restarting. Override with
# e.g. `DEBOUNCE_SECS=3 make debug`.
DEBOUNCE_SECS="${DEBOUNCE_SECS:-10}"
BIN="$(swift build --show-bin-path)/OsumTimer"
APP_PID=""
WATCH_PID=""

stop_app() {
	[ -n "$APP_PID" ] || return 0
	kill "$APP_PID" 2>/dev/null
	wait "$APP_PID" 2>/dev/null
	APP_PID=""
}

start_app() {
	swift build || { echo "--- build failed, waiting for next change ---"; return 0; }
	"$BIN" &
	APP_PID=$!
}

cleanup() {
	trap - INT TERM EXIT
	stop_app
	[ -n "$WATCH_PID" ] && kill "$WATCH_PID" 2>/dev/null
	exit 0
}
# EXIT too: a signal that lands while the shell is blocked in `read` can end the
# script without running the INT/TERM handler, which would orphan the app.
trap cleanup INT TERM EXIT

echo "Watching ${WATCH_PATHS[*]} — Ctrl-C to stop."
start_app

# Keep fswatch in a FIFO rather than a pipeline so the loop (and the trap that
# kills the app) stays in this shell, not a subshell.
FIFO="$(mktemp -u)"
mkfifo "$FIFO"
fswatch -o -l 0.3 -e '/\.build/' "${WATCH_PATHS[@]}" > "$FIFO" &
WATCH_PID=$!
exec 3< "$FIFO"
rm -f "$FIFO"

# Debounce: after the first event, swallow further events until the tree has
# been quiet for DEBOUNCE_SECS. A burst of saves (or a multi-file refactor)
# then costs one restart at the end instead of one per file.
while read -r _ <&3; do
	echo "--- change detected, waiting for ${DEBOUNCE_SECS}s of quiet ---"
	while read -r -t "$DEBOUNCE_SECS" _ <&3; do :; done
	echo "--- restarting ---"
	stop_app
	start_app
	# Discard events that landed while we were rebuilding — otherwise the tail
	# of the burst we just handled would schedule a second, pointless restart.
	# 1s, not a fraction: macOS ships bash 3.2, which rejects fractional -t.
	while read -r -t 1 _ <&3; do :; done
done

cleanup
