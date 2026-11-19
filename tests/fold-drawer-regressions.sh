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
echo 'PASS fold-drawer: each verb calls omarchy-menu correctly; daemon/restart call nothing; unknown exits 2'
