#!/usr/bin/env bash
# omarchy_install_app_icons copies the checkout's applications/icons/*.png into the user's hicolor
# theme under Omarchy's safe_icon_name names, refreshes changed ones, leaves other icons alone, and
# only rebuilds the icon cache when something changed.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME=$work/home CACHE_LOG=$work/cache.log
OMARCHY_PATH=$work/omarchy bin=$work/bin
icons=$OMARCHY_PATH/applications/icons dest=$HOME/.local/share/icons/hicolor/256x256/apps
mkdir -p "$icons" "$bin" "$dest"
printf '#!/bin/sh\necho "$*" >> "$CACHE_LOG"\n' > "$bin/gtk-update-icon-cache"
chmod +x "$bin/gtk-update-icon-cache"
for n in 'Google Contacts' 'Battle.net' Basecamp; do echo "$n" > "$icons/$n.png"; done
echo mine > "$dest/webapp-of-mine.png"

# shellcheck source=../lib/omarchy-move.sh
source "$ROOT/lib/omarchy-move.sh"
run() { ( export PATH="$bin:$PATH" OMARCHY_PATH; omarchy_install_app_icons ); }

run
for n in google-contacts battle-net basecamp; do [[ -f $dest/$n.png ]] || fail "missing $n.png"; done
[[ $(cat "$dest/battle-net.png") == Battle.net ]] || fail 'wrong content for battle-net.png'
[[ $(ls "$dest" | wc -l) == 4 && $(cat "$dest/webapp-of-mine.png") == mine ]] || fail 'touched or added other icons'
[[ $(wc -l < "$CACHE_LOG") == 1 && $(cat "$CACHE_LOG") == *"$HOME/.local/share/icons/hicolor" ]] || fail 'icon cache not rebuilt once'

run
[[ $(wc -l < "$CACHE_LOG") == 1 ]] || fail 'rerun rebuilt the icon cache without a change'

echo changed > "$icons/Basecamp.png"
run
[[ $(cat "$dest/basecamp.png") == changed && $(wc -l < "$CACHE_LOG") == 2 ]] || fail 'changed icon not refreshed'
# An icon already in the target that the fork did not install is the user's (a custom file, a webapp
# icon) and is kept, while one it installed earlier is refreshed. A byte-identical copy is adopted.
echo custom > "$dest/zoom.png"; echo bundled > "$icons/Zoom.png"
echo handmade > "$dest/x.png"; echo handmade > "$icons/X.png"
run
[[ $(cat "$dest/zoom.png") == custom ]] || fail 'a user icon with a bundled name was overwritten'
echo handmade2 > "$icons/X.png"; echo bundled2 > "$icons/Zoom.png"
run
[[ $(cat "$dest/x.png") == handmade2 ]] || fail 'an identical copy was not adopted and refreshed'
[[ $(cat "$dest/zoom.png") == custom ]] || fail 'a user icon was overwritten on a later run'

# A copy that fails (read-only apps dir) must not look like success; the other icons still install.
echo old > "$icons/HEY.png"; run
echo new > "$icons/HEY.png"
chmod a-w "$dest"
if run 2>/dev/null; then chmod u+w "$dest"; fail 'a failed icon copy returned success'; fi
chmod u+w "$dest"
[[ $(cat "$dest/hey.png") == old ]] || fail 'failed copy replaced the icon anyway'
run; [[ $(cat "$dest/hey.png") == new ]] || fail 'icon not installed once the dir is writable again'
echo 'ok'
