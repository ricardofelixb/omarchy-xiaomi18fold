#!/usr/bin/env bash
# Turn Omarchy's idle lock off (.idle.lock = 0 in shell.json; its idle service treats a
# timeout <= 0 as disabled). The container user's password is locked, so the lock screen can
# never be unlocked; Android's own lock protects the phone. Every other key stays, including
# .idle.screensaver. A symlinked file is written through; a missing, read-only or invalid
# file (anything but exactly one JSON object) is left alone with a warning and exit 1;
# running it again changes nothing. Omarchy reads $HOME/.config whatever XDG_CONFIG_HOME says.
set -euo pipefail

file=$HOME/.config/omarchy/shell.json
if [[ -L $file ]]; then file=$(readlink -f -- "$file") || file=''; fi
if [[ ! -f $file || ! -w $file ]] || ! jq -se 'length == 1 and (.[0] | type == "object")' "$file" > /dev/null 2>&1; then
  printf 'WARNING: %s is missing, read-only or not a single JSON object; idle lock left on.\n' "$file" >&2
  exit 1
fi
tmp=$(mktemp -- "$file.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
jq '.idle = ((.idle | if type == "object" then . else {} end) + {lock: 0})' "$file" > "$tmp"
chmod --reference="$file" -- "$tmp"
mv -f -- "$tmp" "$file"
