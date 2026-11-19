#!/usr/bin/env bash
# Set gtk-im-module=fcitx for GTK 3 and GTK 4 apps (XWayland), merged into any existing
# settings.ini. Wayland apps use the text-input frontend, so GTK_IM_MODULE stays unset
# (fcitx5 "Using Fcitx 5 on Wayland"). Keeps other keys and an existing [Settings]
# gtk-im-module value; a symlinked file is edited in place, keeping the link; running it
# again changes nothing.
set -euo pipefail

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
for dir in gtk-3.0 gtk-4.0; do
  file="$config_home/$dir/settings.ini"
  if [[ -L $file ]]; then
    target=$(readlink -f -- "$file") || target=''
    if [[ ! -f $target || ! -w $target ]]; then
      printf 'WARNING: %s is a link to a missing or read-only file; gtk-im-module not set.\n' "$config_home/$dir/settings.ini" >&2
      continue
    fi
    file=$target
  fi
  mkdir -p -- "${file%/*}"
  if [[ ! -s $file ]]; then
    printf '[Settings]\ngtk-im-module=fcitx\n' > "$file"
  elif awk '/^[[:space:]]*\[/ { in_settings = ($0 ~ /^[[:space:]]*\[Settings\][[:space:]]*$/) }
            in_settings && /^[[:space:]]*gtk-im-module[[:space:]]*=/ { found = 1 }
            END { exit !found }' "$file"; then
    continue
  elif grep -Eq '^[[:space:]]*\[Settings\][[:space:]]*$' "$file"; then
    sed -i '0,/^[[:space:]]*\[Settings\][[:space:]]*$/s//[Settings]\ngtk-im-module=fcitx/' "$file"
  else
    printf '\n[Settings]\ngtk-im-module=fcitx\n' >> "$file"
  fi
done
