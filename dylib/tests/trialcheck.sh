#!/bin/sh
# shellcheck disable=SC2034,SC2154
set -e
SRC="${1:-$(dirname "$0")/../feats/compat_run.sh}"
[ -f "$SRC" ] || { echo "trialcheck: $SRC not present, skipped"; exit 0; }

extract() { sed -n "/^$1() {\$/,/^}\$/p" "$SRC"; }
functions=""
for name in alert_safe refuse_ended_trial; do
	body=$(extract "$name")
	[ -n "$body" ] || { echo "FAIL: $name not found in $SRC"; exit 1; }
	functions="$functions
$body"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n         want [%s]\n         got  [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); }
is() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

# The marker's contents, or "absent" for a clone set up under a paid license.
launch() {
	runner=$(mktemp -d "$work/runner.XXXXXX")
	mkdir -p "$runner/CrossOver"
	[ "$1" = absent ] || printf '%s\n' "$1" > "$runner/notproton-trial"
	(
		CX_ROOT="$runner/CrossOver"
		np_build=27.0.0.41073
		np_display="CrossOver Preview"
		log=/dev/null
		# shellcheck disable=SC2329 # called by the extracted refusal
		show_alert() { printf 'alert: %s\n' "$1"; }
		eval "$functions"
		refuse_ended_trial
		echo launched
	) 2>&1 && status=0 || status=$?
	echo "status=$status"
}

now=$(date +%s)
echo "== trial markers =="
is "a clone with no marker launches" "launched
status=0" "$(launch absent)"
is "a trial that has not ended launches" "launched
status=0" "$(launch $((now + 86400)))"
is "a trial that has ended is refused" "alert: The CrossOver trial has ended
status=1" "$(launch $((now - 1)))"
is "a trial ending this second is refused" "alert: The CrossOver trial has ended
status=1" "$(launch "$now")"
is "an empty marker is refused" "alert: The CrossOver trial has ended
status=1" "$(launch "")"
is "a marker that is not a number is refused" "alert: The CrossOver trial has ended
status=1" "$(launch "tomorrow")"

[ "$fails" = 0 ] || { echo "trialcheck: $fails failed"; exit 1; }
echo "==> trialcheck: the run script refuses ended trials"
