#!/usr/bin/env bash
# Regressions for container/bin/fold-hyprgrass-build with fake Hyprland/meson/ninja and a local git
# "hyprgrass" repo: work in the checkout survives, a replaced plugin is rebuilt, no pin fails clearly.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
hl=1111111111111111111111111111111111111111

mkdir -p "$work/bin" "$work/include/glm" "$work/upstream"
touch "$work/include/glm/glm.hpp"
printf '#!/bin/sh\necho "Hyprland 0.0.1 built from branch x at commit $FAKE_HL clean"\n' > "$work/bin/Hyprland"
printf '#!/bin/sh\nexit 0\n' > "$work/bin/pkg-config"
cp "$work/bin/pkg-config" "$work/bin/g++"
printf '#!/bin/sh\n[ "$1" = setup ] && mkdir -p "$2" && echo "$3" > "$2/srcdir"\n' > "$work/bin/meson"
printf '#!/bin/sh\nmkdir -p "$2/src"; echo built > "$2/src/libhyprgrass.so"\n' > "$work/bin/ninja"
chmod +x "$work"/bin/*

git -C "$work/upstream" init -q -b main
git -C "$work/upstream" config user.name t; git -C "$work/upstream" config user.email t@t
echo one > "$work/upstream/file"
git -C "$work/upstream" add file
git -C "$work/upstream" commit -q -m one
pin=$(git -C "$work/upstream" rev-parse HEAD)
printf 'commit_pins = [\n    ["%s", "%s"], # fake\n]\n' "$hl" "$pin" > "$work/upstream/hyprpm.toml"
git -C "$work/upstream" add hyprpm.toml
git -C "$work/upstream" commit -q -m pins
# Upstream's tip no longer has "file", but the pinned commit does.
git -C "$work/upstream" rm -q file
git -C "$work/upstream" commit -q -m 'drop file'

run() {
  PATH="$work/bin:$PATH" FAKE_HL="${FAKE_HL:-$hl}" HYPRGRASS_REPO="$work/upstream" HYPRGRASS_SRC="${SRC:-$work/src}" \
    HYPRGRASS_PLUGIN="$work/plugins/libhyprgrass.so" HYPRGRASS_BUILD="$work/build" \
    HYPRGRASS_INCLUDE_DIR="$work/include" bash "$ROOT/container/bin/fold-hyprgrass-build" 2>&1
}

out=$(run) || fail "first build: $out"
[[ -f $work/plugins/libhyprgrass.so ]] || fail 'plugin not installed'
[[ $(git -C "$work/src" rev-parse HEAD) == "$pin" ]] || fail 'wrong hyprgrass commit checked out'
echo 'PASS builds the pinned commit and installs the plugin'

out=$(run) || fail "rerun: $out"
[[ $out == *'already installed'* ]] || fail "rerun rebuilt: $out"
echo 'PASS rerun skips when the installed plugin matches'

echo replaced > "$work/plugins/libhyprgrass.so"
out=$(run) || fail "after replace: $out"
[[ $out == *Building* && $(cat "$work/plugins/libhyprgrass.so") == built ]] || fail "replaced plugin not rebuilt: $out"
echo 'PASS a plugin replaced behind the stamp is rebuilt'

echo mine >> "$work/src/file"
echo scratch > "$work/src/untracked"
echo replaced > "$work/plugins/libhyprgrass.so"
if out=$(run); then fail "dirty checkout was built over: $out"; fi
[[ $out == *'uncommitted changes'* ]] || fail "unclear dirty message: $out"
grep -qx mine "$work/src/file" && [[ -f $work/src/untracked ]] || fail 'existing work in the checkout was lost'
[[ $(cat "$work/plugins/libhyprgrass.so") == replaced ]] || fail 'plugin touched despite refusal'
echo 'PASS a checkout with uncommitted work is refused and left intact'

git -C "$work/src" checkout -q -- file
if out=$(FAKE_HL=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa run); then fail "no-pin run succeeded: $out"; fi
[[ $out == *'no hyprgrass release pins Hyprland commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'* ]] || fail "unclear no-pin message: $out"
echo 'PASS an unpinned Hyprland commit fails with a clear message'

mkdir -p "$work/src2"
git clone -q "$work/upstream" "$work/src2/hg"
echo file >> "$work/src2/hg/.git/info/exclude"
echo 'precious ignored work' > "$work/src2/hg/file"
if out=$(SRC="$work/src2/hg" run); then fail "ignored file was built over: $out"; fi
[[ $(cat "$work/src2/hg/file") == 'precious ignored work' ]] || fail 'an ignored file in the checkout was overwritten'
echo 'PASS an ignored file the pinned commit tracks is not overwritten'
