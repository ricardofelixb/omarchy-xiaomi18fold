#!/usr/bin/env bash
# Regressions for the display guard's monitor scale: scale 2 for the Terminal app's Full display
# resolution, 1 for Half, and a dispatch only when the scale differs (a repeat would loop on the
# configreloaded event it causes).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$work/bin"
# hyprctl stub: `-j monitors` prints $MON_JSON, `dispatch X` logs X
cat > "$work/bin/hyprctl" <<'STUB'
#!/bin/sh
if [ "$1" = dispatch ]; then echo "$2" >> "$LOG"; else printf '%s\n' "$MON_JSON"; fi
STUB
chmod +x "$work/bin/hyprctl"

fn=$(sed -n '/^scale_for() /p;/^apply_scale() {/,/^}/p' "$ROOT/container/bin/fold-display-guard")
run() { # width height current-scale -> dispatches made
  : > "$work/log"
  PATH="$work/bin:$PATH" LOG="$work/log" \
    MON_JSON="[{\"name\":\"Virtual-1\",\"width\":$1,\"height\":$2,\"scale\":$3}]" \
    bash -c 'log() { :; }; eval "$1"; apply_scale' _ "$fn"
  cat "$work/log"
}
want() { # description width height current-scale expected-scale ("" = no dispatch)
  local got; got=$(run "$2" "$3" "$4")
  if [[ -z $5 ]]; then [[ -z $got ]] || fail "$1: expected no dispatch, got: $got"; return; fi
  [[ $got == *'output = "Virtual-1"'*"scale = $5 })" ]] || fail "$1: expected scale $5, got: ${got:-nothing}"
}

want 'inner Full landscape' 2364 1672 1.00 2
want 'inner Full portrait' 1672 1946 1.00 2
want 'cover Full portrait' 1168 1712 1.00 2
want 'inner Half landscape' 1182 836 2.00 1
want 'inner Half portrait' 836 973 2.00 1
want 'cover Half portrait' 584 856 2.00 1
want 'Full already at 2' 2364 1672 2.00 ''
want 'Half already at 1' 1182 836 1.00 ''
echo 'PASS display scale: 2 on Full, 1 on Half (inner and cover), no repeat dispatch'
