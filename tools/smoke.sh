#!/usr/bin/env bash
# Headless smoke test: new game, outposts + crews + a mining contract, ~10 sim
# minutes fast-forwarded, one summary block (tools/smoke_test.gd).
# Exit 1 on script errors, a crash or a stall. Writes no files.
# Usage: tools/smoke.sh [--minutes N] [--multi] [--explore] [--long] [--forward [--save-roundtrip | --long | --colony]]
#   --multi: also view switches and one mercenary gate round trip (own summary).
#   --explore: an Explorer Outpost, three explorers and one explore contract on
#   Ostra Gate, run until the survey is paid (own summary).
#   --long: 40+ sim minutes on a fixed network seed, with a gate raid summary.
#   --forward: a forward station on Ostra at minute 1 with an outpost, two
#   miners and a contract there; the view stays home (own summary, timings).
#   --save-roundtrip (with --forward): at minute 5 a save to memory and a
#   full reload, then the rest; per-system state must match.
#   --long (with --forward): 26+ sim minutes on a seed with a base in Ostra,
#   a forward merc and zone; forward raids, alarms, upkeep, water, hauling fee.
#   --colony (with --forward, or alone): two Forward Stations built at home
#   and flown with escorts to their planets (one live, one as data), reloads
#   while parked, waiting and in transit (own summary).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
MINUTES=10
MULTI=""
EXPLORE=""
LONG=""
FORWARD=""
ROUNDTRIP=""
COLONY=""
while [ $# -gt 0 ]; do
	case "$1" in
		--minutes) MINUTES="$2"; shift 2 ;;
		--minutes=*) MINUTES="${1#--minutes=}"; shift ;;
		--multi) MULTI="--multi"; shift ;;
		--explore) EXPLORE="--explore"; shift ;;
		--long) LONG="--long"; shift ;;
		--forward) FORWARD="--forward"; shift ;;
		--save-roundtrip) ROUNDTRIP="--save-roundtrip"; shift ;;
		--colony) COLONY="--colony"; shift ;;
		*) echo "unknown arg: $1" >&2; exit 2 ;;
	esac
done
OUT="$("$GODOT" --headless --path . res://tools/smoke_test.tscn -- --minutes="$MINUTES" $MULTI $EXPLORE $LONG $FORWARD $ROUNDTRIP $COLONY 2>&1)"
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
