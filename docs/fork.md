# Fork inventory

Fork of `rwanglq-ctrl/omarchy-xiaomi18fold` (remote `upstream`). Each change below is
listed with its kind (see the fork-maintenance skill), where it lives, and the hook lines it
adds to upstream files.

## Changes

### Release asset URLs point at the published release

- **Kind:** 1, useful to anyone. **Upstream candidate.**
- **Bug:** the installer downloaded pinned assets from
  `gitee.com/zenbardofsuhe/omarchy-xiaomi18fold/releases/download/tools-v0.2.9/`, but that
  Gitee repo has no such release, so every download 404ed (aether, cliamp, omawrite, rime-ice,
  tensaku, ttf-ia-writer, ttfx, yaru-icon-theme, yay, LazyVim).
- **Fix:** all 51 references now use `omarchy-xiaomipad9pm/releases/download/tools-v0.2.9/`,
  where the same files exist. Integrity hashes are unchanged and prove the files are identical.
  `lib/desktop-extras.py` now derives `BASE` from `lib/tool-programs.py`'s `GITEE_ASSET_PATH`,
  so the code has one release base instead of two.
- **Where:** `lib/desktop-extras.py`, `lib/tool-programs.py`, `packages/desktop-extras/aur-assets.json`,
  `packages/desktop-extras/lazyvim-assets.json`, `packages/tool-programs/manifest.json`,
  `scripts/mirror-tool-assets.sh`, `tests/tool-programs-regressions.py`.
- **Drop when:** upstream republishes the `tools-v0.2.9` release under the fold repo, or merges
  the same URL fix.

## Quick checks

- `python3 -B tests/tool-programs-regressions.py`
- `python3 -B tests/desktop-extras-regressions.py`

## Known failures on the base commit

- `python3 -B tests/desktop-tweaks-regressions.py` fails with `ValueError: substring not found`
  (`preset.index('schema: rime_ice')`), also on the commit before this fork change.
