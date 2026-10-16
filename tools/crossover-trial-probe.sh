#!/bin/sh
# Collects, read-only, what an installed CrossOver exposes about its license and trial,
# so CrossOverLicense can get a trial reader backed by evidence instead of a guess.
#
# Read-only: every command below only lists or prints (ls, defaults read, plutil -p,
# grep, strings, mdfind, security without -d). Nothing is written except the report on
# stdout. It does not open bottles, games or saves, and needs no administrator rights.
# The account name, home folder, emails and identifying fields are redacted, but read
# the report before sharing it.
#
#   sh crossover-trial-probe.sh [/path/to/CrossOver.app] > ~/Desktop/crossover-probe.txt

app="${1:-/Applications/CrossOver.app}"
prefs="$HOME/Library/Preferences"
support="$HOME/Library/Application Support"
me=$(id -un)

redact() {
  sed -E \
    -e "s#$HOME#~#g" \
    -e "s#/Users/$me#~#g" \
    -e "s/([[:space:]])$me([[:space:]])/\\1<user>\\2/g" \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g' \
    -e 's/^([[:space:]]*"?(customer|name|email|id|serial|key|login|user|activation|acct|account)[A-Za-z_]*"?[[:space:]]*(<blob>)?[[:space:]]*(=>|=|:)[[:space:]]*).*/\1<redacted>/I'
}

section() { printf '\n===== %s =====\n' "$1"; }

# Lists entries directly inside the given folders whose names mention CrossOver.
named() {
  find "$@" -mindepth 1 -maxdepth 1 \( -iname '*codeweavers*' -o -iname '*crossover*' \
    -o -iname '*cxoffice*' \) -exec ls -ld {} + 2>/dev/null
}

probe() {
  section "probe"
  date -u '+%Y-%m-%dT%H:%M:%SZ'
  sw_vers 2>/dev/null

  section "app"
  if [ ! -d "$app" ]; then
    echo "no CrossOver at $app; candidates:"
    mdfind "kMDItemCFBundleIdentifier == 'com.codeweavers.CrossOver*'" 2>/dev/null
    return 1
  fi
  echo "$app"
  for key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion; do
    printf '%s = %s\n' "$key" "$(defaults read "$app/Contents/Info" "$key" 2>/dev/null)"
  done
  root="$app/Contents/SharedSupport/CrossOver"
  ls -l "$root/share/crossover/data/" 2>/dev/null

  section "license files NotProton checks"
  for dir in "$prefs" /Library/Preferences; do
    for ext in license sha256 sig; do
      f="$dir/com.codeweavers.CrossOver.$ext"
      [ -e "$f" ] && ls -l "$f"
    done
  done
  echo "(nothing listed above means no license file, as expected for a trial)"

  section "CodeWeavers preference files"
  named "$prefs" /Library/Preferences

  section "CodeWeavers preference keys and values"
  for f in "$prefs"/com.codeweavers.*.plist; do
    [ -e "$f" ] || continue
    echo "--- $f"
    plutil -p "$f" 2>/dev/null
  done

  section "CrossOver folders (top level only, bottles are not opened)"
  ls -l "$support/CrossOver" 2>/dev/null
  named "$support" "$HOME/Library/Caches" "$HOME"
  for f in "$support/CrossOver"/*.conf; do
    [ -e "$f" ] || continue
    echo "--- $f"
    cat "$f"
  done

  section "keychain items for CodeWeavers (names only, no secrets)"
  security dump-keychain 2>/dev/null \
    | grep -i -B4 -A8 -E 'codeweavers|crossover' \
    | grep -E '"(svce|labl|desc|cdat|mdat)"' || echo "(none)"

  section "command line tools in the bundle"
  ls "$root/bin" 2>/dev/null

  section "bundle files that mention a trial"
  grep -rIl -i -E 'trial|demo|evaluation' "$root/lib" "$root/share/crossover" 2>/dev/null | head -40

  section "trial strings in the app binary"
  exe=$(defaults read "$app/Contents/Info" CFBundleExecutable 2>/dev/null)
  [ -n "$exe" ] && strings -a "$app/Contents/MacOS/$exe" 2>/dev/null \
    | grep -i -E 'trial|demo|expir|days left|days remaining|register|unlock' | sort -u | head -80
  return 0
}

probe 2>&1 | redact
