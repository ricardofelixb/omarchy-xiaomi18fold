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
echo 'ok   gtk-im-module merge'
