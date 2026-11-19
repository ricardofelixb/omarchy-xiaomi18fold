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
  installed Hyprland; `packages/repo-full.txt` adds `glm`.
- **Where:** `container/install.sh` (helper install list, `build_hyprgrass` step, `hyprgrass`
  report entry), `config/hypr/touch.lua` (header comment), `tests/fold-hyprgrass-build-regressions.sh`.
- **Drop when:** upstream ships an equivalent build step.

### `fold-drawer` subcommands

- **Kind:** 1, useful to anyone. **Upstream candidate:** the guard looped, opening a drawer every pass.
- **Bug:** `fold-drawer` passed `daemon`/`open`/`close`/`toggle`/`restart` to `nwg-drawer`, which opened a visible drawer for each; the guard never saw its daemon (exec renamed it) and started another every pass.
- **Fix:** `container/bin/fold-drawer` now drives Omarchy's own apps menu (`omarchy-menu toggle|summon apps`, `close`); `daemon`/`restart` do nothing. nwg-drawer and its keepalive in `fold-display-guard` and `fold-dismiss-overlays` are gone.
- **Where:** `container/bin/fold-drawer`, `container/bin/fold-display-guard`, `container/bin/fold-dismiss-overlays`, `container/bin/fold-session-rescue`, `tests/fold-drawer-regressions.sh`.
- **Drop when:** upstream fixes `fold-drawer` the same way.

### Fold user services run from `/usr/local/bin`

- **Kind:** 1, useful to anyone. **Upstream candidate:** the clipboard bridge never ran, so Android's Terminal app froze on `wl-paste` every time it regained focus.
- **Bug:** `fold-clip-bridge.service` and `fold-touch-flushd.service` pointed `ExecStart` at paths the installer never writes (status=203/EXEC), and the installer only enabled them when a user manager was running.
- **Fix:** both units use `/usr/local/bin/<name>` (`fold-touch-flushd` through `sudo -n`, it reads `/dev/input`); without a user manager the installer links them into `default.target.wants` as the target user. `lib/fix-user-dirs.py` hands back root-owned folders from older installs without following links; `fold-touch-flushd` opens its log and FIFO without following links.
- **Where:** `host/install.sh` (`install_fold_host_helpers`), `lib/fix-user-dirs.py` (new), `host/fold/bin/fold-touch-flushd`, `host/fold/systemd/user/fold-{clip-bridge,touch-flushd}.service`, `tests/installer-regressions.sh`.
- **Drop when:** upstream fixes the unit paths and enabling the same way.

## Quick checks

- `bash tests/fold-drawer-regressions.sh`
- `bash tests/fold-hyprgrass-build-regressions.sh`; `bash tests/installer-regressions.sh`
- `luac -p config/hypr/*.lua`
- `python3 -B tests/tool-programs-regressions.py`
- `python3 -B tests/desktop-extras-regressions.py`

## Known failures on the base commit

- `python3 -B tests/desktop-tweaks-regressions.py` fails with `ValueError: substring not found`
  (`preset.index('schema: rime_ice')`), also on the commit before this fork change.
