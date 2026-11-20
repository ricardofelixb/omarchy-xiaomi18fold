#!/usr/bin/env bash
# Move the arm-port branch of the Omarchy checkout onto another release, shared by
# container/install.sh (existing installs) and fold-omarchy-update. Source it with OMARCHY_PATH,
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
