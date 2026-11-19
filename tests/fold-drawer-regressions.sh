#!/usr/bin/env bash
# Regressions for container/bin/fold-drawer with stub nwg-drawer/pgrep/pkill on PATH: each
# subcommand must reach nwg-drawer with the right flag, and no subcommand word may leak to it
# (nwg-drawer ignores a stray word and opens a visible drawer, which looped the display guard).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$work/bin"
printf '#!/bin/sh\necho "$*" >> "$LOG"\n' > "$work/bin/nwg-drawer"
printf '#!/bin/sh\necho "pkill $*" >> "$LOG"\n' > "$work/bin/pkill"
# pgrep sees the drawer state in $STATE: none, resident or oneshot.
cat > "$work/bin/pgrep" <<'STUB'
#!/bin/sh
for pattern; do :; done
case $STATE:$pattern in
  resident:*) exit 0 ;;
  oneshot:'^nwg-drawer .* -r$') exit 1 ;;
  oneshot:'^nwg-drawer '*) exit 0 ;;
esac
exit 1
STUB
chmod +x "$work"/bin/*

# run STATE SUBCOMMAND -> the stubs' calls, one per line
run() {
  : > "$work/log"
  PATH="$work/bin:$PATH" LOG="$work/log" STATE=$1 bash "$ROOT/container/bin/fold-drawer" ${2:+"$2"} >/dev/null 2>&1 || true
  sleep 0.8   # restart starts the daemon in the background
  cat "$work/log"
}
expect() { # description state subcommand pattern
  local calls; calls=$(run "$2" "$3")
  grep -Eq -- "$4" <<<"$calls" || fail "$1: expected /$4/, got: ${calls:-nothing}"
  if grep -Eq -- ' (daemon|open|close|toggle|restart)( |$)|^(daemon|open|close|toggle|restart)( |$)' <<<"$calls"; then
    fail "$1: a subcommand word reached nwg-drawer or pkill's nwg-drawer call: $calls"
  fi
}
none() { # description state subcommand
  local calls; calls=$(run "$2" "$3")
  [[ -z $calls ]] || fail "$1: expected no calls, got: $calls"
}

expect 'daemon starts a resident drawer' none daemon '^-wm hyprland .* -closebtn right -r$'
none   'daemon does nothing when resident' resident daemon
expect 'open on a resident drawer' resident open '^-open$'
expect 'open without one starts a one-shot' none open '^-wm hyprland .* -closebtn right$'
none   'open with a one-shot already up does nothing' oneshot open
expect 'close on a resident drawer' resident close '^-close$'
expect 'close with a one-shot kills it' oneshot close '^pkill .*\^nwg-drawer '
expect 'toggle on a resident drawer' resident toggle '^$'
expect 'toggle without one starts a one-shot' none toggle '^-wm hyprland .* -closebtn right$'
expect 'toggle with a one-shot closes it' oneshot toggle '^pkill .*\^nwg-drawer '
expect 'no argument is toggle' none '' '^-wm hyprland '
expect 'restart kills then starts a resident' none restart '^-wm hyprland .* -r$'
: > "$work/log"
[[ $(PATH="$work/bin:$PATH" LOG="$work/log" STATE=none bash "$ROOT/container/bin/fold-drawer" bogus 2>&1; echo "rc=$?") == *'rc=2' ]] || fail 'unknown subcommand must exit 2'
[[ ! -s $work/log ]] || fail 'unknown subcommand reached nwg-drawer'
echo 'PASS fold-drawer: every subcommand reaches nwg-drawer with the right flag; no bare word leaks'
