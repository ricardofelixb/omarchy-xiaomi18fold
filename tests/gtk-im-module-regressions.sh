#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"
unset XDG_CONFIG_HOME
cfg="$HOME/.config"
mkdir -p "$cfg/gtk-3.0" "$cfg/gtk-4.0"
printf '[Settings]\ngtk-application-prefer-dark-theme=1\n[Other]\nx=1\n' > "$cfg/gtk-3.0/settings.ini"
bash "$ROOT/lib/gtk-im-module.sh"
# Existing keys kept, new key added once under [Settings]; missing file created.
[[ $(cat "$cfg/gtk-3.0/settings.ini") == $'[Settings]\ngtk-im-module=fcitx\ngtk-application-prefer-dark-theme=1\n[Other]\nx=1' ]]
[[ $(cat "$cfg/gtk-4.0/settings.ini") == $'[Settings]\ngtk-im-module=fcitx' ]]
before=$(sha256sum "$cfg"/gtk-*/settings.ini)
bash "$ROOT/lib/gtk-im-module.sh"
[[ $(sha256sum "$cfg"/gtk-*/settings.ini) == "$before" ]]
# A user's own value and a file without [Settings] are handled without clobbering.
printf '[Settings]\ngtk-im-module=ibus\n' > "$cfg/gtk-3.0/settings.ini"
printf '[Other]\nx=1\n' > "$cfg/gtk-4.0/settings.ini"
bash "$ROOT/lib/gtk-im-module.sh"
[[ $(cat "$cfg/gtk-3.0/settings.ini") == $'[Settings]\ngtk-im-module=ibus' ]]
[[ $(cat "$cfg/gtk-4.0/settings.ini") == $'[Other]\nx=1\n\n[Settings]\ngtk-im-module=fcitx' ]]
# A key in another section does not count; a symlinked file is merged in place.
printf '[Settings]\nx=1\n[Other]\ngtk-im-module=ibus\n' > "$cfg/gtk-3.0/settings.ini"
mkdir "$work/real"
printf '[Settings]\nx=1\n' > "$work/real/s.ini"
rm "$cfg/gtk-4.0/settings.ini"
ln -s "$work/real/s.ini" "$cfg/gtk-4.0/settings.ini"
bash "$ROOT/lib/gtk-im-module.sh"
[[ $(cat "$cfg/gtk-3.0/settings.ini") == $'[Settings]\ngtk-im-module=fcitx\nx=1\n[Other]\ngtk-im-module=ibus' ]]
[[ -L $cfg/gtk-4.0/settings.ini ]]
[[ $(cat "$work/real/s.ini") == $'[Settings]\ngtk-im-module=fcitx\nx=1' ]]
# GTK accepts an indented [Settings] header; a link to a missing path warns and continues.
printf ' [Settings]\ngtk-im-module=ibus\n' > "$cfg/gtk-3.0/settings.ini"
rm "$cfg/gtk-4.0/settings.ini"
ln -s "$work/no/such/dir/s.ini" "$cfg/gtk-4.0/settings.ini"
bash "$ROOT/lib/gtk-im-module.sh" 2> "$work/warn"
[[ $(cat "$cfg/gtk-3.0/settings.ini") == $' [Settings]\ngtk-im-module=ibus' ]]
grep -q 'gtk-4.0/settings.ini is a link' "$work/warn"
[[ ! -e $work/no ]]
echo 'ok   gtk-im-module merge'
