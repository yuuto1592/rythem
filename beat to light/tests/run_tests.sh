#!/usr/bin/env bash
# Runs the test suite headlessly. Exit code is 0 when every test passes.
#
#   tests/run_tests.sh                     # uses `godot` from PATH
#   GODOT=/path/to/Godot_v4.3 tests/run_tests.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
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

exec "$GODOT" --headless --path "$project_dir" res://tests/test_runner.tscn
