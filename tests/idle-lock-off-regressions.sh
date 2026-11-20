#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"
export XDG_CONFIG_HOME="$work/elsewhere"  # Omarchy ignores it
mkdir -p "$XDG_CONFIG_HOME/omarchy"
printf '{"idle":{"lock":300}}\n' > "$XDG_CONFIG_HOME/omarchy/shell.json"
cfg="$HOME/.config/omarchy/shell.json"
mkdir -p "${cfg%/*}"
run() { bash "$ROOT/lib/idle-lock-off.sh" 2> "$work/warn"; }
skipped() { ! run; grep -q WARNING "$work/warn"; }
# Lock goes to 0; screensaver and every other key stay.
printf '{"bar":{"x":1},"idle":{"screensaver":150,"lock":300}}\n' > "$cfg"
run
[[ $(jq -c . "$cfg") == '{"bar":{"x":1},"idle":{"screensaver":150,"lock":0}}' ]]
before=$(sha256sum "$cfg")
run
[[ $(sha256sum "$cfg") == "$before" ]]
# A missing idle block is added.
printf '{"bar":{"x":1}}\n' > "$cfg"
run
[[ $(jq -c . "$cfg") == '{"bar":{"x":1},"idle":{"lock":0}}' ]]
# Invalid JSON and a missing file stay unchanged, with a warning.
printf '{"idle": {' > "$cfg"
skipped
[[ $(cat "$cfg") == '{"idle": {' ]]
# Two JSON values, or a non-object, are not one object either.
printf '{"idle":{"lock":300}} {"other":1}\n' > "$cfg"
skipped
[[ $(cat "$cfg") == '{"idle":{"lock":300}} {"other":1}' ]]
printf '[]\n' > "$cfg"
skipped
rm "$cfg"
skipped
[[ ! -e $cfg ]]
# A symlinked file is written through, keeping the link.
mkdir "$work/real"
printf '{"idle":{"screensaver":150,"lock":300}}\n' > "$work/real/s.json"
ln -s "$work/real/s.json" "$cfg"
run
[[ -L $cfg ]]
[[ $(jq -c . "$work/real/s.json") == '{"idle":{"screensaver":150,"lock":0}}' ]]
# Omarchy reads $HOME/.config, so XDG_CONFIG_HOME's copy is never touched.
[[ $(jq -c . "$XDG_CONFIG_HOME/omarchy/shell.json") == '{"idle":{"lock":300}}' ]]
echo 'ok   idle lock off'
