#!/usr/bin/env bash
# Headless smoke test: new game, outposts + crews + a mining contract, ~10 sim
# minutes fast-forwarded, one summary block (tools/smoke_test.gd).
# Exit 1 on script errors, a crash or a stall. Writes no files.
# Usage: tools/smoke.sh [--minutes N]
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
MINUTES=10
while [ $# -gt 0 ]; do
	case "$1" in
		--minutes) MINUTES="$2"; shift 2 ;;
		--minutes=*) MINUTES="${1#--minutes=}"; shift ;;
		*) echo "unknown arg: $1" >&2; exit 2 ;;
	esac
done
OUT="$("$GODOT" --headless --path . res://tools/smoke_test.tscn -- --minutes="$MINUTES" 2>&1)"
CODE=$?
echo "$OUT" | grep '^SMOKE'
if echo "$OUT" | grep -q 'SCRIPT ERROR\|Parse Error'; then
	echo "SMOKE script errors in the log:"
	echo "$OUT" | grep -A2 'SCRIPT ERROR\|Parse Error' | head -20
	CODE=1
fi
if ! echo "$OUT" | grep -q '^SMOKE log'; then
	echo "SMOKE FAIL: no summary (crash?). Last lines:"
	echo "$OUT" | tail -20
	exit 1
fi
exit $CODE
