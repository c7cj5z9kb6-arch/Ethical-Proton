#!/bin/sh
# Collects, read-only, what an installed CrossOver exposes about its license and trial,
# so CrossOverLicense can get a trial reader backed by evidence instead of a guess.
# Nothing here writes, moves or deletes anything. Personal values are redacted, but
# read the report before sharing it.
#
#   sh tools/crossover-trial-probe.sh [/path/to/CrossOver.app] > crossover-probe.txt

app="${1:-/Applications/CrossOver.app}"
prefs="$HOME/Library/Preferences"

redact() {
  sed -E \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g' \
    -e 's/^([[:space:]]*"?(customer|name|email|id|serial|key|login|user|activation)[A-Za-z_]*"?[[:space:]]*(=>|=|:)[[:space:]]*).*/\1<redacted>/I'
}

section() { printf '\n===== %s =====\n' "$1"; }

section "probe"
date -u '+%Y-%m-%dT%H:%M:%SZ'
sw_vers 2>/dev/null

section "app"
if [ ! -d "$app" ]; then
  echo "no CrossOver at $app; candidates:"
  mdfind "kMDItemCFBundleIdentifier == 'com.codeweavers.CrossOver*'" 2>/dev/null
  exit 1
fi
echo "$app"
defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null
defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null
defaults read "$app/Contents/Info" CFBundleVersion 2>/dev/null
root="$app/Contents/SharedSupport/CrossOver"
ls -la "$root/share/crossover/data/" 2>/dev/null

section "license files NotProton checks"
for dir in "$prefs" /Library/Preferences; do
  for ext in license sha256 sig; do
    f="$dir/com.codeweavers.CrossOver.$ext"
    [ -e "$f" ] && ls -la "$f"
  done
done
echo "(no output above means no license file, as expected for a trial)"

section "CodeWeavers preference files"
ls -la "$prefs" /Library/Preferences 2>/dev/null | grep -i -E 'codeweavers|crossover'

section "CodeWeavers preference keys and values (redacted)"
for f in "$prefs"/com.codeweavers.*.plist; do
  [ -e "$f" ] || continue
  echo "--- $f"
  plutil -p "$f" 2>/dev/null | redact
done

section "Application Support"
ls -la "$HOME/Library/Application Support/CrossOver" 2>/dev/null
for f in "$HOME/Library/Application Support/CrossOver"/*.conf; do
  [ -e "$f" ] || continue
  echo "--- $f"
  redact < "$f"
done

section "command line tools in the bundle"
ls "$root/bin" 2>/dev/null

section "bundle files that mention a trial"
grep -rIl -i -E 'trial|demo|evaluation' "$root/lib" "$root/share/crossover" 2>/dev/null | head -40

section "trial strings in the app binary"
exe=$(defaults read "$app/Contents/Info" CFBundleExecutable 2>/dev/null)
[ -n "$exe" ] && strings -a "$app/Contents/MacOS/$exe" 2>/dev/null \
  | grep -i -E 'trial|demo|expir|days left|days remaining|register|unlock' | sort -u | head -80
