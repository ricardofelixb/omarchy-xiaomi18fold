#!/usr/bin/env bash
# Regressions for container/bin/fold-omarchy-update with a local "Omarchy" remote and stubbed
# pacman/yay/sudo/omarchy-migrate: arm-port moves to the new tag, a conflict leaves everything
# untouched, the fork's own patches take over when they target the new tag, boot/kernel migrations
# are marked done without running, and a failing migration doesn't stop the rest.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
g() { git -c user.name=t -c user.email=t@t -c advice.detachedHead=false "$@"; }

remote=$work/remote home=$work/home fold=$work/fold bin=$work/bin
export HOME=$home RUN_LOG=$work/run.log
OP=$home/.local/share/omarchy
mkdir -p "$bin" "$home/.local/share" "$fold/container" "$fold/lib" "$fold/patches"
: > "$RUN_LOG"

# Stubs: record what ran. omarchy-migrate lists migrations without a marker, like the real one.
printf '#!/bin/sh\nexec "$@"\n' > "$bin/sudo"
printf '#!/bin/sh\necho "pacman $* UPDATE_PACMAN=$OMARCHY_UPDATE_PACMAN ALLOW=$OMARCHY_ALLOW_DIRECT_PACMAN" >> "$RUN_LOG"\n' > "$bin/pacman"
printf '#!/bin/sh\necho "yay $*" >> "$RUN_LOG"\n' > "$bin/yay"
printf '#!/bin/sh\necho restart-shell >> "$RUN_LOG"\n' > "$bin/omarchy-restart-shell"
printf '#!/bin/sh\necho hyprgrass-build >> "$RUN_LOG"\n' > "$bin/fold-hyprgrass-build"
cat > "$bin/omarchy-migrate" <<'EOF'
#!/bin/bash
[[ ${1:-} == --pending ]] || exit 2
n=1
for f in "$OMARCHY_PATH"/migrations/*.sh; do [[ -f $OMARCHY_MIGRATION_STATE/${f##*/} ]] || { echo "${f##*/}"; n=0; }; done
exit $n
EOF
chmod +x "$bin"/*
printf 'install_config_overlay() { echo overlay >> "$RUN_LOG"; }\n' > "$fold/lib/config-overlay.sh"
cp "$ROOT/lib/omarchy-move.sh" "$fold/lib/"
printf '1000001 # boot loader\n' > "$fold/container/update-skip-migrations.txt"

# Upstream: v1.0.0 has two files and three migrations; v1.1.0 touches b.txt only.
g init -q -b main "$remote"
mkdir "$remote/migrations"
echo alpha > "$remote/a.txt"; echo beta > "$remote/b.txt"
mkdir -p "$remote/applications/icons"; echo icon > "$remote/applications/icons/HEY.png"
for i in 1 2 3; do echo "echo ran-$i >> \"\$RUN_LOG\"" > "$remote/migrations/100000$i.sh"; done
echo 'exit 1' >> "$remote/migrations/1000003.sh"
g -C "$remote" add -A; g -C "$remote" commit -q -m one; g -C "$remote" tag v1.0.0
echo beta2 > "$remote/b.txt"; g -C "$remote" commit -qam two; g -C "$remote" tag v1.1.0

g clone -q --depth 1 --branch v1.0.0 "file://$remote" "$OP"
g -C "$OP" switch -q -c arm-port
echo alpha-fold > "$OP/a.txt"; g -C "$OP" commit -qam 'fold patch'; g -C "$OP" notes --ref=fold add -m fork-patch HEAD
# A user commit on top: the updater's own rebase carries it, and no fallback may ever drop it.
echo mine > "$OP/mine.txt"; g -C "$OP" add mine.txt; g -C "$OP" commit -qm 'user commit'

run() {
  PATH="$bin:$PATH" FOLD_ROOT=$fold FOLD_OMARCHY_REMOTE="${REMOTE:-file://$remote}" bash "$ROOT/container/bin/fold-omarchy-update" 2>&1
}

# 1. Clean move to v1.1.0, with the skip list, a failing migration and the package steps.
out=$(run) || fail "update failed: $out"
[[ $(git -C "$OP" show arm-port:b.txt) == beta2 && $(git -C "$OP" show arm-port:a.txt) == alpha-fold ]] || fail "arm-port not on v1.1.0 with the fold patch: $out"
[[ $(cut -d' ' -f1 "$home/.local/state/fold/omarchy-base") == v1.1.0 ]] || fail 'base not recorded'
git -C "$OP" rev-parse -q --verify arm-port-prev >/dev/null || fail 'no arm-port-prev backup'
[[ -f $home/.local/share/icons/hicolor/256x256/apps/hey.png ]] || fail 'bundled app icons not installed by the update'
grep -q 'pacman -Syu --noconfirm UPDATE_PACMAN=1 ALLOW=1' "$RUN_LOG" || fail "pacman -Syu not run with the guard env: $(cat "$RUN_LOG")"
! grep -q ran-1 "$RUN_LOG" || fail 'skip-listed migration ran'
[[ -f $home/.local/state/omarchy/migrations/1000001.sh ]] || fail 'skip-listed migration not marked done'
grep -q ran-2 "$RUN_LOG" && [[ -f $home/.local/state/omarchy/migrations/1000002.sh ]] || fail 'normal migration not run and marked'
grep -q ran-3 "$RUN_LOG" && [[ ! -f $home/.local/state/omarchy/migrations/1000003.sh ]] || fail 'failing migration must run and stay pending'
grep -q 'failed and will retry next update: 1000003' <<< "$out" || fail "failed migration not reported: $out"
for step in yay overlay restart-shell hyprgrass-build; do grep -q "^$step" "$RUN_LOG" || fail "$step not run"; done

# 2. Conflict with the fork's patch: nothing changes, packages still update.
echo alpha-upstream > "$remote/a.txt"; g -C "$remote" commit -qam three; g -C "$remote" tag v1.2.0
before=$(git -C "$OP" rev-parse arm-port); : > "$RUN_LOG"
out=$(run) || fail "conflict run failed: $out"
grep -q 'Omarchy v1.2.0 needs a fold update; your system is unchanged' <<< "$out" || fail "no conflict message: $out"
[[ $(git -C "$OP" rev-parse arm-port) == "$before" && -z $(git -C "$OP" status --porcelain) ]] || fail 'conflict changed the checkout'
[[ ! -e $OP/.git/rebase-merge && ! -e $OP/.git/rebase-apply ]] || fail 'rebase left in progress'
grep -q 'pacman -Syu' "$RUN_LOG" || fail 'packages not updated after a conflict'
! grep -q 'ran-' "$RUN_LOG" || fail 'migrations ran although Omarchy did not move'

# 2b. The fallback never drops a commit the fork did not make, also after an update rebased it.
# (the shipped patches below target v1.2.0, so only the guard can refuse here)
g -C "$remote" rev-parse v1.2.0 | tr -d '\n' > "$fold/patches/BASE"
g clone -q "file://$remote" "$work/scratch"; g -C "$work/scratch" checkout -q v1.2.0
echo alpha-fold2 > "$work/scratch/a.txt"; g -C "$work/scratch" commit -qam 'fold patch two'
g -C "$work/scratch" format-patch -q -1 -o "$fold/patches"
before=$(git -C "$OP" rev-parse arm-port)
out=$(run) || fail "user-commit run failed: $out"
[[ $(git -C "$OP" rev-parse arm-port) == "$before" && -f $OP/mine.txt ]] || fail "fallback dropped the user commit: $out"
grep -q 'needs a fold update' <<< "$out" || fail "no refusal message: $out"
g -C "$OP" reset -q --hard HEAD~1   # drop the user commit so the fallback may run

# 3. The fork ships patches for v1.2.0 (set up above): they replace the conflicting rebase.
out=$(run) || fail "shipped-patch run failed: $out"
[[ $(git -C "$OP" show arm-port:a.txt) == alpha-fold2 && $(cut -d' ' -f1 "$home/.local/state/fold/omarchy-base") == v1.2.0 ]] || fail "shipped patches not applied: $out"

# 4. No network: say so and still update packages.
: > "$RUN_LOG"
out=$(REMOTE=$work/nowhere run) || fail "offline run failed: $out"
grep -q 'need a global network' <<< "$out" && grep -q 'pacman -Syu' "$RUN_LOG" || fail "offline handling wrong: $out"
# 5. The real overlay in update mode keeps the user's edited config and seeds what is missing.
ov=$work/overlay ovhome=$work/ovhome
mkdir -p "$ov/config/hypr" "$ov/container/bin" "$ovhome/.config/hypr"
echo 'scale = 1' > "$ov/config/hypr/monitors.lua"; echo 'new = 1' > "$ov/config/hypr/touch.lua"
echo 'scale = 2' > "$ovhome/.config/hypr/monitors.lua"
(repo=$ROOT; export HOME=$ovhome ROOT=$ov OMARCHY_PATH=$OP FOLD_KEEP_EXISTING=1; source "$repo/lib/config-overlay.sh"; install_config_overlay 2>/dev/null) || true
[[ $(cat "$ovhome/.config/hypr/monitors.lua") == 'scale = 2' ]] || fail 'update overwrote the existing monitors.lua'
[[ $(cat "$ovhome/.config/hypr/touch.lua") == 'new = 1' ]] || fail 'update did not seed the missing touch.lua'


# 5b. The overlay seeds the Fold's corner radius into shell.toml: new file, existing [bar], a user value kept.
toml=$ovhome/.config/omarchy/shell.toml
overlay() { (repo=$ROOT; export HOME=$ovhome ROOT=$ov OMARCHY_PATH=$OP FOLD_KEEP_EXISTING=1; source "$repo/lib/config-overlay.sh"; install_config_overlay 2>/dev/null) || true; }
overlay
[[ $(cat "$toml") == $'\n[bar]\ncorner-radius = 142' ]] || fail "shell.toml not seeded: $(cat "$toml")"
printf '[font]\nbase-size = 12\n[bar]\nposition = "top"\n' > "$toml"; overlay
[[ $(cat "$toml") == $'[font]\nbase-size = 12\n[bar]\ncorner-radius = 142\nposition = "top"' ]] || fail "existing [bar] not extended: $(cat "$toml")"
printf '[bar]\ncorner-radius = 100\n' > "$toml"; overlay; overlay
[[ $(cat "$toml") == $'[bar]\ncorner-radius = 100' ]] || fail "user corner-radius not kept: $(cat "$toml")"

printf '[bar] # appearance\nposition = "top"\n' > "$toml"; overlay
[[ $(cat "$toml") == $'[bar] # appearance\ncorner-radius = 142\nposition = "top"' ]] || fail "commented [bar] header not extended: $(cat "$toml")"
printf '[other]\ncorner-radius = 12\n' > "$toml"; overlay
[[ $(cat "$toml") == $'[other]\ncorner-radius = 12\n\n[bar]\ncorner-radius = 142' ]] || fail "radius in another section blocked the seed: $(cat "$toml")"
printf '[bar]\nposition = "top"\n' > "$ovhome/real.toml"; rm -f "$toml"; ln -s "$ovhome/real.toml" "$toml"; overlay
[[ -L $toml && $(cat "$ovhome/real.toml") == $'[bar]\ncorner-radius = 142\nposition = "top"' ]] || fail "symlinked shell.toml was replaced or not extended"
rm -f "$toml"
printf '[bar]\nposition = "top"\n' > "$toml"; chmod 444 "$toml"; overlay
[[ $(cat "$toml") == $'[bar]\ncorner-radius = 142\nposition = "top"' && $(stat -c %a "$toml") == 444 ]] || fail "read-only shell.toml not extended with its mode kept: $(cat "$toml")"
chmod 644 "$toml"; rm -f "$toml"

# 4b. A missing skip list leaves every migration pending instead of running them all.
: > "$RUN_LOG"; mv "$fold/container/update-skip-migrations.txt" "$work/skip.bak"
out=$(REMOTE=$work/nowhere run) || true
mv "$work/skip.bak" "$fold/container/update-skip-migrations.txt"
! grep -q 'ran-' "$RUN_LOG" && grep -q 'Skip list .* missing or unreadable' <<< "$out" || fail "migrations ran without a skip list: $out"

# 4c. An unreadable skip list (mode 000) also leaves every migration pending.
if (( $(id -u) != 0 )); then
  : > "$RUN_LOG"; chmod 000 "$fold/container/update-skip-migrations.txt"
  out=$(REMOTE=$work/nowhere run) || true
  chmod 644 "$fold/container/update-skip-migrations.txt"
  ! grep -q 'ran-' "$RUN_LOG" && grep -q 'missing or unreadable' <<< "$out" || fail "migrations ran with an unreadable skip list: $out"
fi

# 6. The installer on a shallow checkout made for an older release (no pinned tag yet) moves it.
inst=$work/inst; mkdir -p "$inst/patches" "$inst/lib"
cp "$ROOT/lib/omarchy-move.sh" "$inst/lib/"
g clone -q --depth 1 --branch v1.0.0 "file://$remote" "$work/old"
g -C "$work/old" switch -q -c arm-port; echo alpha-fold > "$work/old/a.txt"
g -C "$work/old" commit -qam 'fold patch'
g clone -q "file://$remote" "$work/scratch2"; g -C "$work/scratch2" checkout -q v1.1.0
echo alpha-fold > "$work/scratch2/a.txt"; g -C "$work/scratch2" commit -qam 'fold patch'
g -C "$work/scratch2" format-patch -q -1 -o "$inst/patches"
printf '%s fork patch\n' "$(git -C "$work/scratch2" rev-parse 'HEAD^{tree}')" > "$inst/patches/KNOWN-TREES"
g -C "$remote" rev-parse v1.1.0 | tr -d '\n' > "$inst/patches/BASE"
install_fn=$(sed -n '/^clone_and_patch_omarchy() {/,/^}/p' "$ROOT/container/install.sh")
[[ -n $install_fn ]] || fail 'clone_and_patch_omarchy not found'
install_run() {
  HOME=${IHOME:-$work/inst-home} ROOT=${INST:-$inst} OMARCHY_PATH=${OLD:-$work/old} MIRROR=global OMARCHY_TAG=v1.1.0 FOLD_OMARCHY_REMOTE="file://$remote" \
    bash -c "set -eu; $install_fn; clone_and_patch_omarchy" 2>&1
}
# The target tag is already fetched but arm-port still sits on the old release.
g -C "$work/old" fetch -q --depth 1 "file://$remote" refs/tags/v1.1.0:refs/tags/v1.1.0
out=$(install_run) || fail "installer could not upgrade the old checkout: $out"
[[ $(git -C "$work/old" show arm-port:b.txt) == beta2 && $(git -C "$work/old" show arm-port:a.txt) == alpha-fold && $(git -C "$work/old" rev-list --count v1.1.0..arm-port) == 1 ]] || fail "old checkout not moved onto v1.1.0 with one fold commit: $out"
git -C "$work/old" notes --ref=fold show arm-port >/dev/null 2>&1 || fail 'installer did not mark the fork commit'
out=$(install_run) || fail "second installer run failed: $out"
[[ $(git -C "$work/old" rev-list --count v1.1.0..arm-port) == 1 ]] || fail 'second installer run changed the branch'

# 7. An old install without notes whose move conflicts: its commits are recognised from KNOWN-TREES
# and the shipped patches take over; a user commit among them makes the installer refuse.
inst2=$work/inst2; old2=$work/old2; mkdir -p "$inst2/patches" "$inst2/lib"
cp "$ROOT/lib/omarchy-move.sh" "$inst2/lib/"
g clone -q --depth 1 --branch v1.0.0 "file://$remote" "$old2"
g -C "$old2" switch -q -c arm-port; echo beta-fold > "$old2/b.txt"; printf 'l1\ncustom-setting\nl3\nl4\nl5\n' > "$old2/c.txt"
g -C "$old2" add c.txt; g -C "$old2" commit -qam 'fold patch b'
printf '%s fork patch\n' "$(git -C "$old2" rev-parse 'HEAD^{tree}')" > "$inst2/patches/KNOWN-TREES"
g clone -q "file://$remote" "$work/scratch3"; g -C "$work/scratch3" checkout -q v1.1.0
echo beta-fold > "$work/scratch3/b.txt"; printf 'l1\ncustom-setting\nl3\nl4\nl5\n' > "$work/scratch3/c.txt"
g -C "$work/scratch3" add c.txt; g -C "$work/scratch3" commit -qam 'fold patch b'
g -C "$work/scratch3" format-patch -q -1 -o "$inst2/patches"
g -C "$remote" rev-parse v1.1.0 | tr -d '\n' > "$inst2/patches/BASE"
# A whitespace-only edit of a fork commit is the user's change: the fallback must not replace it.
echo 'beta- fold' > "$old2/b.txt"; g -C "$old2" commit -qa --amend --no-edit
before=$(git -C "$old2" rev-parse arm-port)
out=$(IHOME=$work/inst2-home INST=$inst2 OLD=$old2 install_run) && fail "installer replaced a whitespace-edited fork commit: $out"
[[ $(git -C "$old2" rev-parse arm-port) == "$before" && $(git -C "$old2" show arm-port:b.txt) == 'beta- fold' ]] || fail "refused install changed the checkout: $out"
echo beta-fold > "$old2/b.txt"; g -C "$old2" commit -qa --amend --no-edit
# The same line at another place in the file is not the fork's change either.
printf 'l1\nl3\nl4\ncustom-setting\nl5\n' > "$old2/c.txt"; g -C "$old2" commit -qa --amend --no-edit
before=$(git -C "$old2" rev-parse arm-port)
out=$(IHOME=$work/inst2-home INST=$inst2 OLD=$old2 install_run) && fail "installer replaced a fork commit whose line was moved: $out"
[[ $(git -C "$old2" rev-parse arm-port) == "$before" ]] || fail "refused install changed the checkout: $out"
printf 'l1\ncustom-setting\nl3\nl4\nl5\n' > "$old2/c.txt"; g -C "$old2" commit -qa --amend --no-edit
echo mine > "$old2/mine.txt"; g -C "$old2" add mine.txt; g -C "$old2" commit -qm 'user commit'
before=$(git -C "$old2" rev-parse arm-port)
out=$(IHOME=$work/inst2-home INST=$inst2 OLD=$old2 install_run) && fail "installer replaced a conflicting checkout that holds a user commit: $out"
[[ $(git -C "$old2" rev-parse arm-port) == "$before" && -f $old2/mine.txt ]] || fail "refused install changed the checkout: $out"
g -C "$old2" reset -q --hard HEAD~1
out=$(IHOME=$work/inst2-home INST=$inst2 OLD=$old2 install_run) || fail "installer could not move a conflicting old checkout: $out"
[[ $(git -C "$old2" show arm-port:b.txt) == beta-fold && $(git -C "$old2" rev-list --count v1.1.0..arm-port) == 1 ]] || fail "conflicting old checkout not on v1.1.0 with the shipped patch: $out"
echo 'PASS fold-omarchy-update regressions'
