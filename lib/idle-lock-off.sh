#!/usr/bin/env bash
# Turn Omarchy's idle lock off (.idle.lock = 0 in shell.json; its idle service treats a
# timeout <= 0 as disabled). The container user's password is locked, so the lock screen can
# never be unlocked; Android's own lock protects the phone. Every other key stays, including
# .idle.screensaver. A symlinked file is written through; a missing or invalid file is left
# alone with a warning; running it again changes nothing.
set -euo pipefail

file=${XDG_CONFIG_HOME:-"$HOME/.config"}/omarchy/shell.json
if [[ -L $file ]]; then file=$(readlink -f -- "$file") || file=''; fi
if [[ ! -f $file || ! -w $file ]] || ! jq -e 'type == "object"' "$file" > /dev/null 2>&1; then
  printf 'WARNING: %s is missing, read-only or not a JSON object; idle lock left on.\n' "$file" >&2
  exit 0
fi
tmp=$(mktemp -- "$file.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
jq '.idle = ((.idle | if type == "object" then . else {} end) + {lock: 0})' "$file" > "$tmp"
chmod --reference="$file" -- "$tmp"
mv -f -- "$tmp" "$file"
