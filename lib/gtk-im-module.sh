#!/usr/bin/env bash
# Set gtk-im-module=fcitx for GTK 3 and GTK 4 apps (XWayland), merged into any existing
# settings.ini. Wayland apps use the text-input frontend, so GTK_IM_MODULE stays unset
# (fcitx5 "Using Fcitx 5 on Wayland"). Keeps other keys, an existing gtk-im-module value
# and symlinks; running it again changes nothing.
set -euo pipefail

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
for dir in gtk-3.0 gtk-4.0; do
  file="$config_home/$dir/settings.ini"
  [[ -L $file ]] && continue
  mkdir -p -- "${file%/*}"
  if [[ ! -s $file ]]; then
    printf '[Settings]\ngtk-im-module=fcitx\n' > "$file"
  elif grep -Eq '^[[:space:]]*gtk-im-module[[:space:]]*=' "$file"; then
    continue
  elif grep -Eq '^\[Settings\][[:space:]]*$' "$file"; then
    sed -i '0,/^\[Settings\][[:space:]]*$/s//[Settings]\ngtk-im-module=fcitx/' "$file"
  else
    printf '\n[Settings]\ngtk-im-module=fcitx\n' >> "$file"
  fi
done
