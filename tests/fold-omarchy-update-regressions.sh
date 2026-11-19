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
printf '1000001 # boot loader\n' > "$fold/container/update-skip-migrations.txt"

# Upstream: v1.0.0 has two files and three migrations; v1.1.0 touches b.txt only.
g init -q -b main "$remote"
mkdir "$remote/migrations"
echo alpha > "$remote/a.txt"; echo beta > "$remote/b.txt"
for i in 1 2 3; do echo "echo ran-$i >> \"\$RUN_LOG\"" > "$remote/migrations/100000$i.sh"; done
echo 'exit 1' >> "$remote/migrations/1000003.sh"
g -C "$remote" add -A; g -C "$remote" commit -q -m one; g -C "$remote" tag v1.0.0
echo beta2 > "$remote/b.txt"; g -C "$remote" commit -qam two; g -C "$remote" tag v1.1.0

g clone -q --depth 1 --branch v1.0.0 "file://$remote" "$OP"
g -C "$OP" switch -q -c arm-port
echo alpha-fold > "$OP/a.txt"; g -C "$OP" commit -qam 'fold patch'

run() {
  PATH="$bin:$PATH" FOLD_ROOT=$fold FOLD_OMARCHY_REMOTE="${REMOTE:-file://$remote}" bash "$ROOT/container/bin/fold-omarchy-update" 2>&1
}

# 1. Clean move to v1.1.0, with the skip list, a failing migration and the package steps.
out=$(run) || fail "update failed: $out"
[[ $(git -C "$OP" show arm-port:b.txt) == beta2 && $(git -C "$OP" show arm-port:a.txt) == alpha-fold ]] || fail "arm-port not on v1.1.0 with the fold patch: $out"
[[ $(cut -d' ' -f1 "$home/.local/state/fold/omarchy-base") == v1.1.0 ]] || fail 'base not recorded'
git -C "$OP" rev-parse -q --verify arm-port-prev >/dev/null || fail 'no arm-port-prev backup'
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

# 3. The fork ships patches for v1.2.0: they replace the conflicting rebase.
g clone -q "file://$remote" "$work/scratch"; g -C "$work/scratch" checkout -q v1.2.0
echo alpha-fold2 > "$work/scratch/a.txt"; g -C "$work/scratch" commit -qam 'fold patch two'
g -C "$work/scratch" format-patch -q -1 -o "$fold/patches"
g -C "$remote" rev-parse v1.2.0 | tr -d '\n' > "$fold/patches/BASE"
out=$(run) || fail "shipped-patch run failed: $out"
[[ $(git -C "$OP" show arm-port:a.txt) == alpha-fold2 && $(cut -d' ' -f1 "$home/.local/state/fold/omarchy-base") == v1.2.0 ]] || fail "shipped patches not applied: $out"

# 4. No network: say so and still update packages.
: > "$RUN_LOG"
out=$(REMOTE=$work/nowhere run) || fail "offline run failed: $out"
grep -q 'need a global network' <<< "$out" && grep -q 'pacman -Syu' "$RUN_LOG" || fail "offline handling wrong: $out"
echo 'PASS fold-omarchy-update regressions'
