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

### Drop `debug.fifo_pending_workaround` (Hyprland 0.57)

- **Kind:** 1, useful to anyone. **Upstream candidate.**
- **Bug:** Hyprland 0.57 removed the option, so login showed an "unknown config key" banner.
- **Fix:** removed the block from `config/hypr/looknfeel.lua`; there is no replacement.
- **Drop when:** upstream drops the key too.

### Build the hyprgrass touch-gesture plugin

- **Kind:** 1, useful to anyone. **Upstream candidate:** touch gestures never worked without it.
- **Bug:** `config/hypr/touch.lua` loads `libhyprgrass.so`, but nothing built it, so no gesture worked.
- **Fix:** new `container/bin/fold-hyprgrass-build` builds the hyprgrass commit pinned for the
  installed Hyprland; `packages/repo-full.txt` adds `glm` and `nwg-drawer` (the swipe-down app drawer).
- **Where:** `container/install.sh` (helper install list, `build_hyprgrass` step, `hyprgrass`
  report entry), `config/hypr/touch.lua` (header comment), `tests/fold-hyprgrass-build-regressions.sh`.
- **Drop when:** upstream ships an equivalent build step.

## Quick checks

- `bash tests/fold-hyprgrass-build-regressions.sh`; `bash tests/installer-regressions.sh`
- `luac -p config/hypr/*.lua`
- `python3 -B tests/tool-programs-regressions.py`
- `python3 -B tests/desktop-extras-regressions.py`

## Known failures on the base commit

- `python3 -B tests/desktop-tweaks-regressions.py` fails with `ValueError: substring not found`
  (`preset.index('schema: rime_ice')`), also on the commit before this fork change.
