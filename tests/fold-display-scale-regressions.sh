#!/usr/bin/env bash
# Regressions for the display guard's monitor scale: scale 2 for the Terminal app's Full display
# resolution, 1 for Half, and a dispatch only when the scale differs (a repeat would loop on the
# configreloaded event it causes). Fractional scales are compared as they are, not rounded.
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

fn=$(sed -n '/^scale_for() /p;/^declare -A adjusted/p;/^apply_scale() {/,/^}/p' "$ROOT/container/bin/fold-display-guard")
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
  [[ $got == *'output = "Virtual-1"'*"scale = $5 })"* ]] || fail "$1: expected scale $5, got: ${got:-nothing}"
}

want 'inner Full landscape' 2364 1672 1.00 2
want 'inner Full portrait' 1672 1946 1.00 2
want 'cover Full portrait' 1168 1712 1.00 2
want 'inner Half landscape' 1182 836 2.00 1
want 'inner Half portrait' 836 973 2.00 1
want 'cover Half portrait' 584 856 2.00 1
want 'Full already at 2' 2364 1672 2.00 ''
want 'Half already at 1' 1182 836 1.00 ''
want 'Full at 1.5 is not 2' 2364 1672 1.50 2
want 'Half at 1.25 is not 1' 1182 836 1.25 1
want 'Full at 1.99 is not 2' 2364 1672 1.99 2
# event loop: subscribed before the first check, and the backstop fires on elapsed time even when
# events keep arriving faster than the poll interval
printf '#!/bin/sh\ntouch "$WORK/socat-started"\nwhile :; do echo workspacev2\\>\\>1; sleep 0.2; done\n' > "$work/bin/socat"
chmod +x "$work/bin/socat"
loop=$(sed -n '/^# Subscribe before the first check/,$p' "$ROOT/container/bin/fold-display-guard")
: > "$work/checks"
WORK=$work PATH="$work/bin:$PATH" FOLD_POLL_S=2 timeout 6 bash -c '
  POLL_S=$FOLD_POLL_S; SOCKET=x; declare -A popup_since=(); last_active=""; HYPRLAND_INSTANCE_SIGNATURE=t
  log() { :; }; sleep() { command sleep 0.3; }; close_popups() { :; }; popup_watch() { :; }; after_output_change() { :; }
  check() { [[ -e $WORK/socat-started ]] && echo subscribed >> $WORK/checks || echo early >> $WORK/checks; }
  eval "$1"' _ "$loop" >/dev/null 2>&1 || true
[[ $(head -1 "$work/checks") == subscribed ]] || fail "first check ran before subscribing to events"
(( $(wc -l < "$work/checks") >= 3 )) || fail "polling backstop starved by a busy event stream: $(wc -l < "$work/checks") checks in 6 s"

echo 'PASS display scale: 2 on Full, 1 on Half (inner and cover), no repeat dispatch, fractional scales corrected, event loop subscribes first and polls on elapsed time'
