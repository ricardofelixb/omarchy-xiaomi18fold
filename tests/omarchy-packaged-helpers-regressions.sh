#!/usr/bin/env bash
# Regressions for omarchy_install_packaged_helpers (lib/omarchy-move.sh): the helpers Omarchy's package
# keeps at /usr/bin are installed as root-owned copies with their sudoers rules, a rule visudo rejects is
# not installed, a missing helper is reported, and the installer and updater both call it. Also
# omarchy_seed_home_defaults: the one-time home files Omarchy's quattro upgrade makes (screensaver and
# about branding, nautilus extensions, agent skill link) are created when missing and never overwritten.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

bin=$work/bin OP=$work/omarchy dest=$work/dest
export RUN_LOG=$work/run.log
mkdir -p "$bin" "$OP/bin" "$OP/etc/sudoers.d"; : > "$RUN_LOG"
# Stubs: sudo runs the command; install records its flags and drops -o/-g (the test user is not root);
# visudo rejects a file containing BROKEN, as the real one rejects bad syntax.
printf '#!/bin/sh\nexec "$@"\n' > "$bin/sudo"
cat > "$bin/install" <<'STUB'
#!/bin/bash
echo "install $*" >> "$RUN_LOG"
args=(); while (($#)); do case $1 in -o|-g) shift 2 ;; *) args+=("$1"); shift ;; esac; done
exec /usr/bin/install "${args[@]}"
STUB
cat > "$bin/visudo" <<'STUB'
#!/bin/bash
echo "visudo $*" >> "$RUN_LOG"
! grep -q BROKEN "${@: -1}"
STUB
chmod +x "$bin"/*
printf '#!/bin/bash\necho theme\n' > "$OP/bin/omarchy-theme-set-browser-policy"
printf '#!/bin/bash\necho locale\n' > "$OP/bin/omarchy-locale-generate"
echo '%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-theme-set-browser-policy [0-9a-f]' > "$OP/etc/sudoers.d/omarchy-theme-browser"
echo '%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-locale-generate en' > "$OP/etc/sudoers.d/omarchy-locale-generate"

run() { (export PATH="$bin:$PATH" OMARCHY_PATH=$OP OMV_PACKAGED_ROOT=$dest; source "$ROOT/lib/omarchy-move.sh"; omarchy_install_packaged_helpers 2>&1); }

# 1. Both helpers and both rules land as copies (not links), root-owned and with the package's modes.
out=$(run) || fail "install failed: $out"
for h in omarchy-theme-set-browser-policy omarchy-locale-generate; do
  [[ -f $dest/usr/bin/$h && ! -L $dest/usr/bin/$h ]] && cmp -s "$OP/bin/$h" "$dest/usr/bin/$h" || fail "$h is not a copy in /usr/bin"
done
cmp -s "$OP/etc/sudoers.d/omarchy-theme-browser" "$dest/etc/sudoers.d/omarchy-theme-browser" || fail 'theme sudoers rule not installed'
[[ $(stat -c %a "$dest/usr/bin/omarchy-locale-generate") == 755 && $(stat -c %a "$dest/etc/sudoers.d/omarchy-theme-browser") == 440 ]] || fail 'modes are not 755/440'
[[ $(grep -c -- '-o root -g root' "$RUN_LOG") == 4 ]] || fail "installs must be root-owned: $(cat "$RUN_LOG")"
[[ $(grep -c '^visudo -cqf' "$RUN_LOG") == 2 ]] || fail 'rules not validated with visudo -cf'

# 2. A rule visudo rejects is not installed, the other pair still is, and the run reports failure.
rm -rf "$dest"; echo BROKEN > "$OP/etc/sudoers.d/omarchy-theme-browser"
out=$(run) && fail 'a rejected sudoers rule must fail the run'
[[ ! -e $dest/etc/sudoers.d/omarchy-theme-browser && -e $dest/etc/sudoers.d/omarchy-locale-generate ]] || fail 'rejected rule installed, or the good pair skipped'
grep -q 'Could not install omarchy-theme-set-browser-policy' <<< "$out" || fail "no message: $out"

# 3. A helper missing from the checkout is named and nothing is installed for it.
rm -rf "$dest"; rm "$OP/bin/omarchy-locale-generate"
out=$(run) && fail 'a missing helper must fail the run'
grep -q 'no omarchy-locale-generate' <<< "$out" && [[ ! -e $dest/usr/bin/omarchy-locale-generate && ! -e $dest/etc/sudoers.d/omarchy-locale-generate ]] || fail "missing helper handling wrong: $out"

# 5. A home without the quattro one-time files gets them; files the user already has are left alone.
rm -rf "${OP:?}/default" "${work:?}/home"; mkdir -p "$OP/default/nautilus-python/extensions" "$OP/default/agents/skills/omarchy" "$work/home/.config/omarchy/branding"
echo icon > "$OP/icon.txt"; echo logo > "$OP/logo.txt"; echo ext > "$OP/default/nautilus-python/extensions/localsend.py"; echo ext2 > "$OP/default/nautilus-python/extensions/transcode.py"
seed() { (HOME=$work/home OMARCHY_PATH=$OP; source "$ROOT/lib/omarchy-move.sh"; omarchy_seed_home_defaults); }
echo custom > "$work/home/.config/omarchy/branding/screensaver.txt"
seed; b=$work/home/.config/omarchy/branding
[[ $(cat "$b/screensaver.txt") == custom ]] || fail 'an existing screensaver.txt was overwritten'
[[ $(cat "$b/about.txt") == icon ]] || fail 'missing about.txt not created'
rm -rf "$b"; seed
[[ $(cat "$b/about.txt") == icon && $(cat "$b/screensaver.txt") == logo ]] || fail 'a home without branding/ must get both files'
[[ -f $work/home/.local/share/nautilus-python/extensions/transcode.py && -L $work/home/.agents/skills/omarchy ]] || fail 'nautilus extensions or the agent skill link missing'
echo mine > "$work/home/.local/share/nautilus-python/extensions/localsend.py"; seed
[[ $(cat "$work/home/.local/share/nautilus-python/extensions/localsend.py") == mine ]] || fail 'an existing nautilus extension was overwritten'

# 4. The installer and the updater both call it.
grep -q 'omarchy_install_packaged_helpers' <(sed -n '/^install_system_helpers() {/,/^}/p' "$ROOT/container/install.sh") || fail 'installer does not install the helpers'
grep -q 'omarchy_install_packaged_helpers' "$ROOT/container/bin/fold-omarchy-update" || fail 'updater does not refresh the helpers'
grep -q 'omarchy_seed_home_defaults' <(sed -n '/^seed_omarchy_config() {/,/^}/p' "$ROOT/container/install.sh") || fail 'installer does not seed the home defaults'
grep -q 'omarchy_seed_home_defaults' "$ROOT/container/bin/fold-omarchy-update" || fail 'updater does not seed the home defaults'
echo 'omarchy packaged helper regressions passed'
