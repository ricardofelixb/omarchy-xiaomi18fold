#!/usr/bin/env bash
# The fold config overlay, shared by container/install.sh and fold-omarchy-update.
# Source it with ROOT (the fork checkout or the payload) and OMARCHY_PATH set.
install_input_defaults() {
  local target="$HOME/.config/hypr/input.lua"
  local baseline="$HOME/.local/state/omarchy-alarm/input.lua"
  local known_default=false hash
  if [[ -f $target && ! -L $target ]]; then
    hash=$(sha256sum "$target" | cut -d ' ' -f1)
    # Exact v0.2.0–v0.2.8 blob, interim v0.2.9 overlay, and released v0.2.9.
    case "$hash" in
      db40a8d86e57673cc37d3183c3307c4b98d0ff48839a46ef31d4cad1d400f805|a99d3741cd4070d9a32b6b301adda1f15273f876ae1b9438e4336db7734e1a5e|6ad1625ed77bda8fc6b0cd0921929ef6f796017a8a523b3af420a7600e5f2abe) known_default=true ;;
    esac
  fi
  # Only replace absent or byte-identical installer/upstream defaults. Never
  # follow a user symlink or overwrite an edited input file on repeat installs.
  if [[ ! -L $target ]] && { [[ ! -e $target ]] ||
      cmp -s "$target" "$baseline" ||
      cmp -s "$target" "$ROOT/config/hypr/input.lua" ||
      cmp -s "$target" "$OMARCHY_PATH/config/hypr/input.lua" ||
      $known_default; }; then
    install -Dm644 "$ROOT/config/hypr/input.lua" "$target"
    install -Dm644 "$ROOT/config/hypr/input.lua" "$baseline"
  else
    install -Dm644 "$ROOT/config/hypr/input.lua" "$baseline.dist"
    echo "Preserved edited/symlinked $target; reviewed defaults: $baseline.dist"
  fi
}
# The Fold's inner screen has 142 px corners that clip the bar's end widgets. Seed the radius into the
# user's shell.toml (patch 0008 reads it) when no corner-radius is set; a value the user wrote stays.
install_bar_corner_radius() {
  local toml real tmp
  local bar_header='^[[:space:]]*\[bar\][[:space:]]*(#.*)?$'   # indentation or a trailing comment is valid TOML
  toml="$HOME/.config/omarchy/shell.toml"
  mkdir -p "${toml%/*}" || return 1
  real=$(readlink -f "$toml")   # replace the symlink's target, not the symlink
  # Nothing to do when [bar] already sets a radius (one in another table doesn't count).
  [[ ! -e $real ]] || ! awk -v hdr="$bar_header" '
    /^[[:space:]]*\[/ { inbar = ($0 ~ hdr) }
    inbar && /^[[:space:]]*corner-radius[[:space:]]*=/ { found = 1 }
    END { exit !found }' "$real" || return 0
  [[ -e $real ]] || : > "$real" || return 1
  tmp=$(mktemp "$real.XXXXXX") || return 1
  if awk -v hdr="$bar_header" '
    $0 ~ hdr && !n { n = NR }
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) { print line[i]; if (i == n) print "corner-radius = 142" }
      if (!n) print "\n[bar]\ncorner-radius = 142"
    }' "$real" > "$tmp" && chmod --reference="$real" "$tmp" && mv -f "$tmp" "$real"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}
install_config_overlay() {
  local file relative rc=0
  while IFS= read -r -d '' file; do
    relative=${file#"$ROOT/config/"}
    # This file is merged by configure_build_directories, not overwritten.
    [[ $relative != pacman/makepkg.conf ]] || continue
    if [[ $relative == hypr/input.lua ]]; then install_input_defaults; continue; fi
    # An update only seeds what is missing: monitors.lua, foot.ini, kitty.conf and the like hold the
    # user's scale and font size, and the installer's own edits.
    if [[ -n ${FOLD_KEEP_EXISTING:-} && ( -e $HOME/.config/$relative || -L $HOME/.config/$relative ) ]]; then continue; fi
    # IME preferences are absent-only seeds, including dangling user symlinks.
    if [[ $relative == fcitx5/* && ( -e $HOME/.config/$relative || -L $HOME/.config/$relative ) ]]; then continue; fi
    install -Dm644 "$file" "$HOME/.config/$relative"
  done < <(find "$ROOT/config" -type f -print0)
  install -Dm755 "$ROOT/container/bin/fcitx5-autostart" "$HOME/.local/bin/fcitx5-autostart" || rc=1
  # Xiaomi 18 Fold helpers (display guard, touch flush, dock, OSK toggle, window menu)
  for _fold_bin in fold-display-guard fold-window-menu fold-touch-flush-req fold-dismiss-overlays \
      fold-session-rescue omarchy-osk-toggle fold-dock fold-drawer fold-hyprgrass-build fold-omarchy-update; do
    if [[ -f $ROOT/container/bin/$_fold_bin ]]; then
      install -Dm755 "$ROOT/container/bin/$_fold_bin" "$HOME/.local/bin/$_fold_bin" || rc=1
    fi
  done
  install -Dm755 "$ROOT/container/bin/host-run" "$HOME/.local/bin/host-run" || rc=1
  install -Dm755 "$ROOT/container/bin/portal-autostart" "$HOME/.local/bin/portal-autostart" || rc=1
  install -Dm755 "$ROOT/container/bin/lock-ime-reset-autostart" "$HOME/.local/bin/lock-ime-reset-autostart" || rc=1
  # Seed last so a failure skips none of the installs above; any failed install or seed is the status.
  install_bar_corner_radius || rc=1
  return "$rc"
}
# fold-omarchy-update runs without the fork checkout, so keep a copy of what it needs.
install_fold_payload() {
  local dest="$HOME/.local/share/fold"
  rm -rf -- "$dest.new"; mkdir -p "$dest.new/container" "$dest.new/lib"
  cp -a "$ROOT/config" "$ROOT/patches" "$dest.new/"
  cp -a "$ROOT/container/bin" "$ROOT/container/update-skip-migrations.txt" "$dest.new/container/"
  cp -a "$ROOT/lib/config-overlay.sh" "$ROOT/lib/omarchy-move.sh" "$dest.new/lib/"
  rm -rf -- "$dest"; mv -T "$dest.new" "$dest"
}
