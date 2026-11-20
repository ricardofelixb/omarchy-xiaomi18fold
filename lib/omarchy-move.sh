#!/usr/bin/env bash
# Move the arm-port branch of the Omarchy checkout onto another release, and install the packaged-path
# helpers from it; shared by container/install.sh (existing installs) and fold-omarchy-update. Source it with OMARCHY_PATH,
# OMARCHY_REMOTE, FOLD_STATE and FOLD_PATCHES (the patches folder with BASE) set.
# Returns 1 and leaves the checkout as it was when the move is not possible.
omv_git() { git -C "$OMARCHY_PATH" -c advice.detachedHead=false -c notes.rewriteRef=refs/notes/fold -c user.name=omarchy-alarm-nspawn -c user.email=noreply@example.com "$@"; }
omv_warn() { printf '\e[33m%s\e[0m\n' "$*" >&2; }

# Prints "<tag> <commit>" for the release arm-port sits on: the recorded one, else the nearest tag.
omv_current_base() {
  local tag
  if [[ -s $FOLD_STATE/omarchy-base ]]; then cat "$FOLD_STATE/omarchy-base"; return; fi
  tag=$(omv_git describe --tags --abbrev=0 --match 'v[0-9]*' arm-port 2>/dev/null) || return 1
  echo "$tag $(omv_git rev-parse "$tag^{commit}")"
}

# The fork's commits carry a note in refs/notes/fold (rebase copies it). Anything without one is the user's.
omv_mark_fork() { omv_git notes --ref=fold add -f -m fork-patch "$1" >/dev/null 2>&1; }
# Marks the commits in $1..HEAD whose tree is one the fork shipped (patches/KNOWN-TREES). A tree match is exact:
# any edit of a fork commit, or a user commit below it, changes the tree, so only untouched fork commits get
# the note. Called before a move too, so installs made before the notes existed keep the fallback.
omv_mark_fork_commits() {
  local commit
  for commit in $(omv_git rev-list "$1..HEAD"); do
    grep -q "^$(omv_git rev-parse "$commit^{tree}") " "$FOLD_PATCHES/KNOWN-TREES" 2>/dev/null && omv_mark_fork "$commit"
  done
  return 0
}

# Rebuild arm-port from the fork's own patches when the rebase conflicts and they target this tag.
# Refused when arm-port holds a commit without the fork's note: it would be lost.
omv_apply_shipped_patches() {
  local new=$1 old=$2 patch commit
  [[ $(tr -d '\n' < "$FOLD_PATCHES/BASE" 2>/dev/null) == "$new" ]] || return 1
  for commit in $(omv_git rev-list "$old..arm-port"); do
    omv_git notes --ref=fold show "$commit" >/dev/null 2>&1 || return 1
  done
  omv_git switch -q --detach "$new" || return 1
  for patch in "$FOLD_PATCHES"/*.patch; do
    omv_git am -q "$patch" >/dev/null 2>&1 || { omv_git am --abort >/dev/null 2>&1; omv_git switch -q arm-port; return 1; }
    omv_mark_fork HEAD
  done
  omv_git branch -f arm-port HEAD >/dev/null && omv_git switch -q arm-port
}

omarchy_move_to() {
  local tag=$1 old_tag old new tip
  read -r old_tag old < <(omv_current_base) || { omv_warn 'Cannot tell which Omarchy release arm-port is on; Omarchy left as it is.'; return 1; }
  if [[ $old_tag == "$tag" || $(printf '%s\n%s\n' "$old_tag" "$tag" | sort -V | tail -n 1) == "$old_tag" ]]; then
    echo "Omarchy $old_tag is the latest release."; return 0
  fi
  if [[ $(omv_git branch --show-current) != arm-port || -n $(omv_git status --porcelain) ]]; then
    omv_warn "Omarchy $tag is out, but the Omarchy checkout is not a clean arm-port; your system is unchanged."; return 1
  fi
  omv_mark_fork_commits "$old"
  omv_git fetch -q --depth 1 "$OMARCHY_REMOTE" "refs/tags/$tag:refs/tags/$tag" || { omv_warn "Could not fetch Omarchy $tag; your system is unchanged."; return 1; }
  new=$(omv_git rev-parse "$tag^{commit}") && tip=$(omv_git rev-parse arm-port) || return 1
  if ! omv_git rebase -q --onto "$new" "$old" arm-port >/dev/null 2>&1; then
    omv_git rebase --abort >/dev/null 2>&1
    if ! omv_apply_shipped_patches "$new" "$old"; then
      omv_warn "Omarchy $tag needs a fold update; your system is unchanged."; return 1
    fi
  fi
  omv_git branch -f arm-port-prev "$tip" >/dev/null
  mkdir -p "$FOLD_STATE"; echo "$tag $new" > "$FOLD_STATE/omarchy-base"
  echo "Omarchy moved from $old_tag to $tag (previous arm-port kept as arm-port-prev)."
}

# Omarchy's package puts some helpers at /usr/bin/omarchy-* and their sudoers rules in /etc/sudoers.d; a git
# checkout has neither, so theme and language changes that call those paths fail. Copy (never link: a sudoers
# rule must not name a user-writable file) the ones that work in the container, as "helper:rule" pairs.
# Left out on purpose: omarchy-dns (needs NetworkManager/systemd-resolved; the fork writes the container's
# resolv.conf), the timezone rule (no timedated), omarchy-sudo-passwordless/-shell and the boot, kernel,
# hibernation, hardware, factory-reset, provisioning and systemd-service helpers.
OMV_PACKAGED_HELPERS=(omarchy-theme-set-browser-policy:omarchy-theme-browser omarchy-locale-generate:omarchy-locale-generate)
# Trust: the files come from the user-writable checkout and visudo only checks syntax. That is accepted
# because the user is already passwordless root in this container (the fork's installer sets it up and
# Omarchy's update flow relies on sudo), so there is no privilege boundary to protect. If that is ever
# tightened, this needs a trust anchor (pinned sums or a verified fetch of the release).
# OMV_PACKAGED_ROOT is a test-only prefix for /usr/bin and /etc/sudoers.d. Returns 1 if any pair was not installed.
omarchy_install_packaged_helpers() {
  local pair helper rule tmp failed=0 root=${OMV_PACKAGED_ROOT:-}
  for pair in "${OMV_PACKAGED_HELPERS[@]}"; do
    helper=${pair%%:*} rule=${pair##*:}
    if [[ ! -f $OMARCHY_PATH/bin/$helper || ! -f $OMARCHY_PATH/etc/sudoers.d/$rule ]]; then
      omv_warn "Omarchy has no $helper or its sudoers rule $rule; not installed."; failed=1; continue
    fi
    # The helper first, so a rule never names a missing file; the rule only after visudo accepts it.
    tmp=$(mktemp) && cp -- "$OMARCHY_PATH/etc/sudoers.d/$rule" "$tmp" || { failed=1; continue; }
    if sudo install -Dm755 -o root -g root "$OMARCHY_PATH/bin/$helper" "$root/usr/bin/$helper" </dev/null &&
       sudo visudo -cqf "$tmp" </dev/null &&
       sudo install -Dm440 -o root -g root "$tmp" "$root/etc/sudoers.d/$rule" </dev/null; then :
    else omv_warn "Could not install $helper with its sudoers rule $rule."; failed=1; fi
    rm -f -- "$tmp"
  done
  return "$failed"
}

# Omarchy's package installs applications/icons/*.png as hicolor icons named by its safe_icon_name
# (lowercase, runs of non-alphanumerics -> "-"); a git checkout has no package, so launcher entries
# that use those themed names show the gear. Copies into the user's theme (no root). An icon already
# there is the user's (a custom file, a webapp icon) unless it is byte-identical to the bundled one or
# matches the checksum recorded when this function installed it ($FOLD_STATE/app-icons), so only the
# fork's own icons are refreshed. Needs OMARCHY_PATH. Returns 1 if any icon could not be copied (the
# rest are still installed).
omarchy_install_app_icons() {
  local theme=$HOME/.local/share/icons/hicolor png name dst sum changed=0 failed=0
  local record=${FOLD_STATE:-$HOME/.local/state/fold}/app-icons
  mkdir -p "$theme/256x256/apps" "${record%/*}" || return 1
  touch "$record" || return 1
  for png in "$OMARCHY_PATH"/applications/icons/*.png; do
    [[ -f $png ]] || continue
    name=$(basename "$png" .png | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//')
    dst=$theme/256x256/apps/$name.png
    if [[ -e $dst ]] && ! cmp -s "$png" "$dst"; then
      sum=$(sha256sum "$dst" | cut -d' ' -f1)
      grep -Fxq "$name $sum" "$record" || continue
    fi
    if [[ ! -e $dst ]] || ! cmp -s "$png" "$dst"; then
      if install -m644 "$png" "$dst"; then changed=1; else failed=1; continue; fi
    fi
    { grep -v "^$name " "$record"; echo "$name $(sha256sum "$dst" | cut -d' ' -f1)"; } > "$record.new" || true
    mv -f "$record.new" "$record" || failed=1
  done
  # -t: the user theme dir has no index.theme of its own.
  ((changed)) && { gtk-update-icon-cache -q -t "$theme" || true; }
  return "$failed"
}

# Omarchy's package seeds these through /etc/skel and its quattro upgrade creates them once; neither runs here,
# so a fresh install or a 4.0.4 -> 4.5 move lacked them (the screensaver looped "Error reading input file";
# the Projects bookmark pointed at a folder nobody made). Mirrors that upgrade's steps, but only for what is
# missing: nothing the user has is overwritten. Returns 1 if any step failed (it still tries the rest).
# Skipped on purpose: the XDG settings and Downloads/Pictures/Videos handling the fork's home-layout and
# omarchy-provision-user already do, hypr toggles/flags.lua (Hyprland copes without it), and everything else
# the upgrade does (Limine, systemd --user, keyring, hardware).
omarchy_seed_home_defaults() {
  local root=$OMARCHY_PATH ext dir bookmark failed=0 skill=$OMARCHY_PATH/default/agents/skills
  local branding=$HOME/.config/omarchy/branding ext_dir=$HOME/.local/share/nautilus-python/extensions
  mkdir -p "$branding" "$ext_dir" || failed=1
  [[ ! -f $root/icon.txt ]] || cp --update=none -- "$root/icon.txt" "$branding/about.txt" || failed=1
  [[ ! -f $root/logo.txt ]] || cp --update=none -- "$root/logo.txt" "$branding/screensaver.txt" || failed=1
  for ext in localsend.py transcode.py; do
    [[ ! -f $root/default/nautilus-python/extensions/$ext ]] || cp --update=none -- "$root/default/nautilus-python/extensions/$ext" "$ext_dir/" || failed=1
  done
  mkdir -p "$HOME/.config/gtk-3.0" || failed=1
  touch "$HOME/.config/gtk-3.0/bookmarks" || failed=1
  for dir in Downloads Projects Pictures Videos; do
    # A user file with a folder's name stays as it is (as lib/home-layout.sh does); the folder is skipped.
    [[ -e $HOME/$dir || -L $HOME/$dir ]] || mkdir -p "$HOME/$dir" || failed=1
    bookmark="file://$HOME/$dir $dir"
    grep -qxF "$bookmark" "$HOME/.config/gtk-3.0/bookmarks" && continue
    # An existing last line without a newline must not swallow the new entry.
    [[ -z $(tail -c1 "$HOME/.config/gtk-3.0/bookmarks") ]] || echo >> "$HOME/.config/gtk-3.0/bookmarks" || failed=1
    echo "$bookmark" >> "$HOME/.config/gtk-3.0/bookmarks" || failed=1
  done
  if [[ -d $skill/omarchy ]]; then
    for dir in .agents .claude .codex .pi/agent; do
      mkdir -p "$HOME/$dir/skills" || { failed=1; continue; }
      [[ -e $HOME/$dir/skills/omarchy || -L $HOME/$dir/skills/omarchy ]] || ln -s "$skill/omarchy" "$HOME/$dir/skills/omarchy" || failed=1
    done
  fi
  return "$failed"
}
