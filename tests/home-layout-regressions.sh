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
# ~/go is never deleted: it may hold personal files, even under pkg/mod.
mkdir -p "$work/go-home/go/pkg/mod"; echo keep > "$work/go-home/go/pkg/mod/my-notes.txt"
HOME=$work/go-home XDG_CONFIG_HOME=$work/go-home/.config bash "$ROOT/lib/home-layout.sh" 2>/dev/null
[[ $(cat "$work/go-home/go/pkg/mod/my-notes.txt") == keep ]] || { echo 'FAIL: ~/go content deleted'; exit 1; }
# Rerunning the installer refreshes an existing managed makepkg block (older ones lack GOPATH).
upg=$work/upgrade-home; mkdir -p "$upg/.config/pacman"
printf 'MAKEFLAGS=-j2\n\n# BEGIN omarchy-alarm build\nBUILDDIR=$HOME/.cache/makepkg\nexport TMPDIR=$HOME/.cache/tmp\n# END omarchy-alarm build\nPKGEXT=.keep\n' > "$upg/.config/pacman/makepkg.conf"
run_cbd() { HOME=$upg ROOT=$ROOT bash -c "$(sed -n '/^configure_build_directories()/,/^}/p' "$ROOT/container/install.sh"); configure_build_directories"; }
run_cbd
conf=$upg/.config/pacman/makepkg.conf
[[ $(grep -c '^export GOPATH=' "$conf") == 1 ]] || { echo 'FAIL: existing makepkg block not given GOPATH'; exit 1; }
grep -Fxq 'MAKEFLAGS=-j2' "$conf" && grep -Fxq 'PKGEXT=.keep' "$conf" || { echo 'FAIL: lines outside the managed block lost'; exit 1; }
before=$(sha256sum "$conf"); run_cbd
[[ $(sha256sum "$conf") == "$before" ]] || { echo 'FAIL: makepkg block not idempotent'; exit 1; }
# A block without its end marker, or a failed rewrite, must leave makepkg.conf untouched.
printf 'MAKEFLAGS=-j2\n# BEGIN omarchy-alarm build\nBUILDDIR=old\nPKGEXT=.keep\n' > "$conf"
before=$(sha256sum "$conf"); ! run_cbd 2>/dev/null || { echo 'FAIL: block without end marker must stop the installer'; exit 1; }
[[ $(sha256sum "$conf") == "$before" ]] || { echo 'FAIL: block without end marker was rewritten'; exit 1; }
printf '# BEGIN omarchy-alarm build\nBUILDDIR=old\n# END omarchy-alarm build\nPKGEXT=.keep\n' > "$conf"; chmod 640 "$conf"
before=$(sha256sum "$conf"); mkdir -p "$work/badawk"; printf '#!/bin/sh\nexit 1\n' > "$work/badawk/awk"; chmod +x "$work/badawk/awk"
! PATH=$work/badawk:$PATH run_cbd 2>/dev/null || { echo 'FAIL: failed rewrite must stop the installer'; exit 1; }
[[ $(sha256sum "$conf") == "$before" ]] || { echo 'FAIL: failed rewrite changed makepkg.conf'; exit 1; }
run_cbd
[[ $(stat -c %a "$conf") == 640 && $(grep -c '^export GOPATH=' "$conf") == 1 && $(ls "$upg/.config/pacman" | wc -l) == 1 ]] || { echo 'FAIL: rewrite changed mode or left temp files'; exit 1; }
# End marker before the begin marker is malformed: stop and leave makepkg.conf untouched.
printf 'MAKEFLAGS=-j2\n# END omarchy-alarm build\n# BEGIN omarchy-alarm build\nPKGEXT=.keep\n' > "$conf"
before=$(sha256sum "$conf"); ! run_cbd 2>/dev/null || { echo 'FAIL: misordered markers must stop the installer'; exit 1; }
[[ $(sha256sum "$conf") == "$before" ]] || { echo 'FAIL: misordered markers were rewritten'; exit 1; }
# Every test in tests/run.sh is a separate command.
! grep -Eq '\.(sh|py)"[[:space:]]*bash ' "$ROOT/tests/run.sh" || { echo 'FAIL: tests/run.sh joins two commands without a separator'; exit 1; }
# A symlinked makepkg.conf stays a symlink; its target gets the refresh.
mv "$conf" "$upg/dotfile-makepkg.conf"; ln -s "$upg/dotfile-makepkg.conf" "$conf"
run_cbd
[[ -L $conf && $(grep -c '^export GOPATH=' "$upg/dotfile-makepkg.conf") == 1 ]] || { echo 'FAIL: symlinked makepkg.conf replaced or not refreshed'; exit 1; }
for package in uwsm hyprland-guiutils ttf-jetbrains-mono-nerd tree-sitter-cli; do
  grep -Fxq "$package" "$ROOT/packages/repo-core.txt"
done
grep -Fq 'step initialize_home_layout ' "$ROOT/container/install.sh"
grep -Fq 'pacman -Si yaru-icon-theme' "$ROOT/container/install.sh"
echo 'PASS home layout, existing-file preservation, and core desktop packages'
