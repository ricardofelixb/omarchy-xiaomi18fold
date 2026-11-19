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
# Hyprland adjusts 2 to ~1.83 at 2365x1672: no re-request per check; a reload (scale back to 1)
# re-requests; a dispatch that changed nothing is retried. Stateful stub: dispatch sets the scale.
cat > "$work/bin/hyprctl" <<'STUB'
#!/bin/sh
if [ "$1" = dispatch ]; then
  echo "$2" >> "$LOG"; [ -n "$FAIL" ] && exit 0
  want=$(printf '%s' "$2" | sed 's/.*scale = \([0-9.]*\) .*/\1/'); echo "${ADJ:-$want}" > "$STATE"
else
  printf '[{"name":"Virtual-1","width":2365,"height":1672,"scale":%s}]\n' "$(cat "$STATE")"
fi
STUB
cycle() { # start-scale checks -> dispatch count; env ADJ / FAIL as given
  echo "$1" > "$work/state"; : > "$work/log"
  PATH="$work/bin:$PATH" LOG="$work/log" STATE="$work/state" ADJ="${ADJ:-}" FAIL="${FAIL:-}" \
    bash -c 'log() { :; }; eval "$1"; for _ in $(seq "$2"); do apply_scale; done' _ "$fn" "$2"
  wc -l < "$work/log"
}
[[ $(ADJ=1.83 cycle 1 4) == 1 ]] || fail 'adjusted scale re-requested on every check'
: > "$work/log"
PATH="$work/bin:$PATH" LOG="$work/log" STATE="$work/state" ADJ=1.83 bash -c 'log() { :; }; eval "$1"; echo 1 > "$STATE"; apply_scale; apply_scale; echo 1 > "$STATE"; apply_scale; apply_scale' _ "$fn"
[[ $(wc -l < "$work/log") == 2 ]] || fail "reload did not re-request the scale: $(cat "$work/log")"
[[ $(FAIL=1 cycle 1 3) == 3 ]] || fail 'failed dispatch was not retried'

# event loop: subscribed before the first check, and the backstop fires on elapsed time even when
# events keep arriving faster than the poll interval
printf '#!/bin/sh\n# like socat: fail at once when the socket is missing\nfor a; do :; done; [ -S "${a#UNIX-CONNECT:}" ] || exit 1\ntouch "$WORK/socat-started"\nwhile :; do echo workspacev2\\>\\>1; sleep 0.2; done\n' > "$work/bin/socat"
chmod +x "$work/bin/socat"
loop=$(sed -n '/^# Subscribe before the first check/,$p' "$ROOT/container/bin/fold-display-guard")
: > "$work/checks"
# the socket appears one second after the guard starts (Hyprland still starting)
(command sleep 1; exec python3 -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); time.sleep(8)' "$work/ev.sock") &
sockpid=$!
WORK=$work PATH="$work/bin:$PATH" FOLD_POLL_S=2 timeout 6 bash -c '
  POLL_S=$FOLD_POLL_S; SOCKET=$WORK/ev.sock; declare -A popup_since=(); last_active=""; HYPRLAND_INSTANCE_SIGNATURE=t
  log() { :; }; sleep() { command sleep 0.3; }; close_popups() { :; }; popup_watch() { :; }; after_output_change() { :; }
  check() { [[ -e $WORK/socat-started ]] && echo subscribed >> $WORK/checks || echo early >> $WORK/checks; }
  eval "$1"' _ "$loop" >/dev/null 2>&1 || true
kill "$sockpid" 2>/dev/null || true
[[ $(head -1 "$work/checks") == subscribed ]] || fail "first check ran before subscribing to events"
(( $(wc -l < "$work/checks") >= 3 )) || fail "guard died or polling backstop starved by a busy event stream: $(wc -l < "$work/checks") checks in 6 s"

echo 'PASS display scale: 2 on Full, 1 on Half (inner and cover), no repeat dispatch, fractional scales corrected, event loop subscribes first and polls on elapsed time'
