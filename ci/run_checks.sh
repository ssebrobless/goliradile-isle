#!/usr/bin/env bash
# Runs the game's headless test and simulation tools, then compares the results with
# ci/baselines.json. Usage: GODOT=/path/to/godot ci/run_checks.sh
# Update the exact balance table after an intentional balance change:
#   GODOT=... ci/run_checks.sh --update-balance
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=ci/out
mkdir -p "$OUT"
rm -f "$OUT"/*.txt

run() {  # name, then the arguments after "--"
  local name="$1"; shift
  echo "== $name"
  timeout 600 "$GODOT" --headless --path . -- "$@" > "$OUT/$name.txt" 2>&1
  echo $? > "$OUT/$name.exit"
}

run selftest --selftest
run balance --balance
run soak --soak --runs=6 --secs=20
run defense --defense

python3 ci/check.py "$OUT" "$@"
