#!/usr/bin/env bash
# Parses every script in the project and prints only the errors. Fast: nothing runs.
#   tools/check_scripts.sh
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
cd "$(dirname "$0")/.."
for f in scripts/*.gd dev/*.gd dev/checks/*.gd dev/looks/*.gd; do
  [ -f "$f" ] || continue
  out=$("$G" --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error|at: GDScript" | grep -v "Failed to compile depended" | grep -v "Identifier not found: Game" | grep -B0 -A1 "ERROR" | grep -v "^--$")
  [ -n "$out" ] && echo "== $f" && echo "$out"
done
exit 0
