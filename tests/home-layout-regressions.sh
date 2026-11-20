#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"
unset XDG_CONFIG_HOME
mkdir -p "$HOME"
bash "$ROOT/lib/home-layout.sh"
for name in Work Desktop Documents Downloads Music Pictures Projects Public Templates Videos; do
  [[ -d $HOME/$name ]]
done
[[ $(wc -l < "$HOME/.config/user-dirs.dirs") == 8 ]]
grep -Fx 'XDG_PUBLICSHARE_DIR="$HOME/Public"' "$HOME/.config/user-dirs.dirs"
before=$(sha256sum "$HOME/.config/user-dirs.dirs")
bash "$ROOT/lib/home-layout.sh"
[[ $(sha256sum "$HOME/.config/user-dirs.dirs") == "$before" ]]

# Preserve content and choices; never source arbitrary existing XDG config.
printf 'touch "%s/should-not-exist"\n' "$work" > "$HOME/.config/user-dirs.dirs"
rmdir "$HOME/Work" "$HOME/Documents" "$HOME/Templates"
printf 'existing work file\n' > "$HOME/Work"
ln -s "$work/missing-target" "$HOME/Documents"
mkdir "$work/user-templates"
ln -s "$work/user-templates" "$HOME/Templates"
before=$(sha256sum "$HOME/Work" "$HOME/.config/user-dirs.dirs")
bash "$ROOT/lib/home-layout.sh"
[[ $(sha256sum "$HOME/Work" "$HOME/.config/user-dirs.dirs") == "$before" ]]
[[ -L $HOME/Documents && ! -e $work/missing-target ]]
[[ -L $HOME/Templates && ! -e $work/should-not-exist ]]
rm "$HOME/.config/user-dirs.dirs"
ln -s "$work/missing-config" "$HOME/.config/user-dirs.dirs"
bash "$ROOT/lib/home-layout.sh"
[[ -L $HOME/.config/user-dirs.dirs && ! -e $work/missing-config ]]

export XDG_CONFIG_HOME="$work/custom-config"
bash "$ROOT/lib/home-layout.sh"
[[ -f $XDG_CONFIG_HOME/user-dirs.dirs ]]
# ~/go is removed only when it holds nothing but a real module cache directory.
go_home() { rm -rf "$work/go-home"; mkdir -p "$work/go-home"; }
run_go() { HOME=$work/go-home XDG_CONFIG_HOME=$work/go-home/.config bash "$ROOT/lib/home-layout.sh" 2>/dev/null; }
go_home; mkdir -p "$work/go-home/go/pkg/mod/cache/x"; chmod -R a-w "$work/go-home/go/pkg/mod"
run_go; [[ ! -e $work/go-home/go ]] || { echo 'FAIL: pure module cache ~/go not removed'; exit 1; }
go_home; mkdir -p "$work/go-home/go/pkg"; echo keep > "$work/go-home/go/pkg/mod"
run_go; [[ $(cat "$work/go-home/go/pkg/mod") == keep ]] || { echo 'FAIL: file at ~/go/pkg/mod deleted'; exit 1; }
go_home; mkdir -p "$work/go-home/go/pkg/mod" "$work/go-home/go/bin"
run_go; [[ -d $work/go-home/go/bin ]] || { echo 'FAIL: ~/go with bin deleted'; exit 1; }
go_home; mkdir -p "$work/go-home/go/pkg/mod" "$work/go-home/go/pkg/other"
run_go; [[ -d $work/go-home/go/pkg/other ]] || { echo 'FAIL: ~/go/pkg with other entries deleted'; exit 1; }
go_home; mkdir -p "$work/go-home/go/pkg" "$work/go-target/f"; ln -s "$work/go-target" "$work/go-home/go/pkg/mod"
run_go; [[ -d $work/go-target/f && -L $work/go-home/go/pkg/mod ]] || { echo 'FAIL: symlinked module cache removed'; exit 1; }
go_home; mkdir -p "$work/go-target2/pkg/mod"; ln -s "$work/go-target2" "$work/go-home/go"
run_go; [[ -d $work/go-target2/pkg/mod && -L $work/go-home/go ]] || { echo 'FAIL: symlinked ~/go removed'; exit 1; }
for package in uwsm hyprland-guiutils ttf-jetbrains-mono-nerd tree-sitter-cli; do
  grep -Fxq "$package" "$ROOT/packages/repo-core.txt"
done
grep -Fq 'step initialize_home_layout ' "$ROOT/container/install.sh"
grep -Fq 'pacman -Si yaru-icon-theme' "$ROOT/container/install.sh"
echo 'PASS home layout, existing-file preservation, and core desktop packages'
