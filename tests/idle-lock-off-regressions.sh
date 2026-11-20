#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"
export XDG_CONFIG_HOME="$work/elsewhere"  # Omarchy ignores it
mkdir -p "$XDG_CONFIG_HOME/omarchy"
printf '{"version":1,"idle":{"lock":300}}\n' > "$XDG_CONFIG_HOME/omarchy/shell.json"
cfg="$HOME/.config/omarchy/shell.json"
mkdir -p "${cfg%/*}"
run() { bash "$ROOT/lib/idle-lock-off.sh" 2> "$work/warn"; }
skipped() { ! run; grep -q WARNING "$work/warn"; }
# Lock goes to 0; screensaver and every other key stay.
printf '{"version":1,"bar":{"x":1},"idle":{"screensaver":150,"lock":300}}\n' > "$cfg"
run
[[ $(jq -c . "$cfg") == '{"version":1,"bar":{"x":1},"idle":{"screensaver":150,"lock":0}}' ]]
before=$(sha256sum "$cfg")
run
[[ $(sha256sum "$cfg") == "$before" ]]
# A missing idle block is added; a missing version becomes 1, as in Omarchy's own editors
# (without it Omarchy ignores the file and keeps lock=300).
printf '{"version":1,"bar":{"x":1}}\n' > "$cfg"
run
[[ $(jq -c . "$cfg") == '{"version":1,"bar":{"x":1},"idle":{"lock":0}}' ]]
printf '{"bar":{"x":1}}\n' > "$cfg"
run
[[ $(jq -c . "$cfg") == '{"version":1,"bar":{"x":1},"idle":{"lock":0}}' ]]
# A version Omarchy would ignore is not edited, and is not reported as applied.
printf '{"version":2,"idle":{"lock":300}}\n' > "$cfg"
skipped
[[ $(jq -c . "$cfg") == '{"version":2,"idle":{"lock":300}}' ]]
printf '{"version":true,"idle":{"lock":300}}\n' > "$cfg"
skipped
# Invalid JSON and a missing file stay unchanged, with a warning.
printf '{"idle": {' > "$cfg"
skipped
[[ $(cat "$cfg") == '{"idle": {' ]]
# Two JSON values, or a non-object, are not one object either.
printf '{"version":1,"idle":{"lock":300}} {"other":1}\n' > "$cfg"
skipped
[[ $(cat "$cfg") == '{"version":1,"idle":{"lock":300}} {"other":1}' ]]
# jq accepts NaN and rewrites it as null; strict JSON does not.
printf '{"version":1,"idle":{"lock":300},"x":NaN}\n' > "$cfg"
skipped
[[ $(cat "$cfg") == '{"version":1,"idle":{"lock":300},"x":NaN}' ]]
printf '[]\n' > "$cfg"
skipped
rm "$cfg"
skipped
[[ ! -e $cfg ]]
# A symlinked file is written through, keeping the link.
mkdir "$work/real"
printf '{"version":1,"idle":{"screensaver":150,"lock":300}}\n' > "$work/real/s.json"
ln -s "$work/real/s.json" "$cfg"
run
[[ -L $cfg ]]
[[ $(jq -c . "$work/real/s.json") == '{"version":1,"idle":{"screensaver":150,"lock":0}}' ]]
# Omarchy reads $HOME/.config, so XDG_CONFIG_HOME's copy is never touched.
[[ $(jq -c . "$XDG_CONFIG_HOME/omarchy/shell.json") == '{"version":1,"idle":{"lock":300}}' ]]
echo 'ok   idle lock off'
