#!/usr/bin/env bash
# Regressions for container/bin/fold-drawer with a stub omarchy-menu on PATH: each verb must call
# it with the right arguments, daemon/restart must call nothing (the Omarchy shell is resident)
# and an unknown verb must exit 2.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$work/bin"
printf '#!/bin/sh\necho "omarchy-menu $*" >> "$LOG"\n' > "$work/bin/omarchy-menu"
chmod +x "$work/bin/omarchy-menu"

# run VERB... -> the stub's calls (one line per call), then "rc=N"
run() {
  : > "$work/log"
  local rc=0
  PATH="$work/bin:$PATH" LOG="$work/log" bash "$ROOT/container/bin/fold-drawer" "$@" >/dev/null 2>&1 || rc=$?
  cat "$work/log"; echo "rc=$rc"
}
expect() { # verb expected-call ("" = no call); a missing call must not pass
  local want='rc=0' got
  [[ -z $2 ]] || want=$2$'\n'rc=0
  got=$(run $1)
  [[ $got == "$want" ]] || fail "'$1': expected ${2:-no call}, got: ${got//$'\n'/ }"
}

expect toggle 'omarchy-menu toggle apps'
expect '' 'omarchy-menu toggle apps'
expect open 'omarchy-menu summon apps'
expect close 'omarchy-menu close'
expect daemon ''
expect restart ''
got=$(run bogus)
[[ $got == 'rc=2' ]] || fail "unknown verb must exit 2 without calling omarchy-menu, got: ${got//$'\n'/ }"

# The display guard closes a leftover apps menu (omarchy-menu layer) on an output change, as it
# did the old drawer; stubbed hyprctl lists the layers, fold-drawer/fold-window-menu log calls.
guard_calls() { # layer namespaces listed by hyprctl, one per line -> calls made by after_output_change
  printf '#!/bin/sh\nfor ns in $LAYERS; do echo "namespace: $ns,"; done\n' > "$work/bin/hyprctl"
  printf '#!/bin/sh\necho "fold-drawer $*" >> "$LOG"\n' > "$work/bin/fold-drawer"
  printf '#!/bin/sh\necho "fold-window-menu $*" >> "$LOG"\n' > "$work/bin/fold-window-menu"
  chmod +x "$work"/bin/*
  : > "$work/log"
  PATH="$work/bin:$PATH" LOG="$work/log" LAYERS=$1 SECONDS=100 bash -c '
    last_popup_close=0
    eval "$(sed -n "/^close_popups() {/,/^}/p;/^after_output_change() {/,/^}/p" "$1")"
    after_output_change' _ "$ROOT/container/bin/fold-display-guard"
  cat "$work/log"
}
[[ $(guard_calls 'omarchy-menu omarchy-bar') == 'fold-drawer close' ]] || fail 'output change must close an open apps menu with fold-drawer close'
[[ $(guard_calls 'fold-window-menu') == 'fold-window-menu close' ]] || fail 'output change must still close the window menu'
[[ -z $(guard_calls 'omarchy-bar') ]] || fail 'output change must not close anything when no popup is open'
echo 'PASS fold-drawer: each verb calls omarchy-menu correctly; daemon/restart call nothing; unknown exits 2; the guard closes a leftover apps menu'
