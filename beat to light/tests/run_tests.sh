#!/usr/bin/env bash
# Runs the test suite headlessly. Exit code is 0 when every test passes.
#
#   tests/run_tests.sh                     # uses `godot` from PATH
#   GODOT=/path/to/Godot_v4.7.2 tests/run_tests.sh
#   TEST_TIMEOUT=300 tests/run_tests.sh    # raise the time limit (seconds)
set -euo pipefail

GODOT="${GODOT:-godot}"
# The suite normally takes seconds. The limit exists because a script that
# fails to parse leaves Godot idling on an empty scene instead of exiting.
TEST_TIMEOUT="${TEST_TIMEOUT:-90}"
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot not found: '$GODOT'. Set GODOT to your Godot 4 binary." >&2
	exit 2
fi

# A fresh checkout has no .godot/ yet, and without the import step the global
# class names (Chart, Judge, ...) are unknown and every script fails to parse.
if [ ! -f "$project_dir/.godot/global_script_class_cache.cfg" ]; then
	echo "Importing project (first run only)..."
	"$GODOT" --headless --editor --quit --path "$project_dir" >/dev/null 2>&1 || true
fi

# `timeout` is GNU coreutils; macOS has it as `gtimeout` (brew install coreutils).
run_capped() {
	if command -v timeout >/dev/null 2>&1; then
		timeout "$TEST_TIMEOUT" "$@"
	elif command -v gtimeout >/dev/null 2>&1; then
		gtimeout "$TEST_TIMEOUT" "$@"
	else
		"$@"
	fi
}

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

status=0
run_capped "$GODOT" --headless --path "$project_dir" res://tests/test_runner.tscn 2>&1 \
	| tee "$log" || status=$?

if [ "$status" -eq 124 ]; then
	echo "" >&2
	echo "Timed out after ${TEST_TIMEOUT}s. This almost always means a script failed" >&2
	echo "to parse: look for 'SCRIPT ERROR' above." >&2
elif [ "$status" -eq 0 ] && ! grep -qE '^[0-9]+ passed, 0 failed' "$log"; then
	# Code under test that quits the game (the editor's "quit" after its
	# unsaved-changes question, say) ends the run early with exit code 0.
	echo "" >&2
	echo "Godot exited before the suite finished: no summary line was printed." >&2
	echo "Something quit the game early, in the test after the last one listed above." >&2
	status=3
fi
exit "$status"
