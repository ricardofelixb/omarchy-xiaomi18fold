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

### Drop `GTK_IM_MODULE`, set `gtk-im-module` in GTK settings

- **Kind:** 1, useful to anyone. **Upstream candidate.**
- **Bug:** with `GTK_IM_MODULE=fcitx` set, fcitx5 shows a "Wayland Diagnose" notification at login.
- **Fix:** `config/hypr/envs.lua` no longer sets it (matches Omarchy). GTK 3/4 apps under XWayland
  still need fcitx, so `lib/gtk-im-module.sh` merges `gtk-im-module=fcitx` into
  `~/.config/gtk-{3,4}.0/settings.ini` (fcitx5 Wayland docs); keeps other keys and an existing value.
- **Where:** `config/hypr/envs.lua`, `lib/gtk-im-module.sh`, `container/install.sh` (one step),
  `tests/gtk-im-module-regressions.sh`.
- **Drop when:** never needed upstream; drop if Omarchy ships these settings.

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

### English window menu and `uwsm-app` messages

- **Kind:** 2, the user's preference over upstream's Chinese text. Fork-only, not an upstream candidate; strings are replaced in place (no language setting) to keep upstream merges easy.
- **Change:** on-screen text of `container/bin/fold-window-menu` and the `uwsm-app` error message and comments are English; comments naming those buttons use the new names.
- **Where:** `container/bin/fold-window-menu`, `container/bin/uwsm-app`, comment lines in `config/hypr/autostart.lua`, `config/hypr/touch.lua`, `container/bin/fold-dismiss-overlays`, `host/fold/bin/fold-touch-flush`, `host/fold/bin/fold-touch-flushd`.
- **Drop when:** never, unless upstream adopts English text.

### Omarchy's Update System works on the Fold

- **Kind:** 3, machine-specific (the Arch ARM container has no `[omarchy]` repo, kernel or boot loader). Fork-only.
- **Bug:** `omarchy-update` was unusable here (`docs/troubleshooting.md` said not to run it), so Omarchy stayed on v4.0.4.
- **Fix:** `container/bin/fold-omarchy-update` rebases `arm-port` onto the newest release tag (on a conflict: aborts, says so, and falls back to the fork's own `patches/` when `patches/BASE` is that tag and every commit on `arm-port` carries the fork note in `refs/notes/fold`, which the installer and the updater set (a commit gets it only when its git tree is listed in `patches/KNOWN-TREES`, the trees after every patch of every series the fork shipped; `tests/run.sh --check patches` fails until a refreshed series is appended; rebase copies the note; any edited fork commit or user commit makes it refuse), runs `pacman -Syu` and `yay -Sua`, runs pending migrations except those in `container/update-skip-migrations.txt` (boot/kernel, marked done), re-applies the config overlay and restarts the shell. Without a move there are no migrations, and without the skip list none run either; the fallback is refused when `arm-port` holds commits the fork did not make. The rebase code is `lib/omarchy-move.sh`, which the installer also uses to move an existing older checkout onto the pin. Patch 0007 makes `bin/omarchy-update` exec it. The overlay moved to `lib/config-overlay.sh`; the installer keeps a copy of patches, config and the overlay in `~/.local/share/fold` for it. Patches 0001-0006 were refreshed onto v4.5.0 (old 0004, the Qt colors fix, is upstream now) and the pin moved to `omacom/omarchy` v4.5.0.
- **Where:** `container/bin/fold-omarchy-update`, `container/update-skip-migrations.txt`, `lib/config-overlay.sh`, `lib/omarchy-move.sh`, `patches/KNOWN-TREES`, `container/install.sh` (pin, source line, one step), `patches/*`, `tests/fold-omarchy-update-regressions.sh`, `tools/privacy-allowlist.txt` (moved hash line), `README.md`, `docs/troubleshooting.md`.
- **Known follow-up:** the CN vendored tarball (`vendor/`, `lib/network.sh`) is still Omarchy v4.0.4, so a fresh CN install fails the v4.5.0 pin check until it is refreshed; release updates have no CN mirror.
- **Drop when:** upstream ships an ARM package set and `omarchy-update` works on Arch Linux ARM.

### Container DNS resolves tailnet names

- **Kind:** 1, useful to anyone with Tailscale on the host. **Upstream candidate.**
- **Bug:** the container shares the VM's network but its static `resolv.conf` skips Tailscale's MagicDNS, so tailnet IPs work and names do not.
- **Fix:** with `tailscale` on the host, `network_resolv_config` puts `nameserver 100.100.100.100` first, keeps the first two other servers (glibc reads three; CN fallback too), and adds `options timeout:2` and the MagicDNS `search` suffix when `tailscale status --json` gives one.
- **Where:** `lib/network.sh` (`network_resolv_config`), `README.md`, `tests/installer-regressions.sh`.
- **Drop when:** upstream sets up container DNS from the host's resolver.

### Packaged Omarchy helpers installed from the checkout

- **Kind:** 1, useful to anyone running Omarchy from a git checkout. **Upstream candidate.**
- **Bug:** Omarchy's package puts `omarchy-theme-set-browser-policy` and `omarchy-locale-generate` at `/usr/bin` with sudoers rules; a checkout has neither, so every theme change said "Theme not applied everywhere: omarchy-theme-set-browser failed".
- **Fix:** `omarchy_install_packaged_helpers` copies those two and their rules (root-owned, no links, `visudo -cf`) from the checkout at install and after each `fold-omarchy-update`. Not installed: `omarchy-dns` (needs NetworkManager/systemd-resolved), the timezone rule, and the boot, kernel, hibernation, hardware, factory-reset and service helpers.
- **Trust:** the rules are trusted because the user is already passwordless root here; if that is ever tightened, this needs a trust anchor (pinned sums or a verified fetch of the release).
- **Where:** `lib/omarchy-move.sh`, `container/install.sh`, `container/bin/fold-omarchy-update`, `tests/omarchy-packaged-helpers-regressions.sh`, `tests/run.sh`.
- **Drop when:** upstream ships an ARM package set, or the checkout path gets a dev-link rule for these helpers.

### Launcher apps show their real icons

- **Kind:** 1, useful to anyone running Omarchy from git. **Upstream candidate.**
- **Bug:** Omarchy 4.5's desktop entries use themed icon names (`basecamp`, `google-contacts`, ...); its package installs `applications/icons/*.png` as hicolor icons, a git checkout doesn't, so most launcher apps showed the gear.
- **Fix:** `omarchy_install_app_icons` copies each icon to `~/.local/share/icons/hicolor/256x256/apps/<safe_icon_name>.png` (Omarchy's naming rule), refreshing only icons it installed itself (checksums in `~/.local/state/fold/app-icons`; a user's own icon with the same name is kept); run by `container/install.sh` and `fold-omarchy-update`.
- **Where:** `lib/omarchy-move.sh`, `container/install.sh`, `container/bin/fold-omarchy-update`, `tests/omarchy-app-icons-regressions.sh`.
- **Drop when:** upstream's installer provides the bundled icons without its package.

### Bar clears the rounded screen corners

- **Kind:** 1, useful to anyone with a rounded panel (patch `0008`), plus a Fold-only seed. **Upstream candidate.**
- **Bug:** on the unfolded Fold the inner screen's 142 px corners clip the bar's first and last widgets; the cutouts file only describes a top notch, and a Hyprland reserved area doesn't move widgets sideways.
- **Fix:** patch `0008` adds `[bar] corner-radius` (physical px, default 0): the bar starts its side widgets where the corner circle meets the bar at a quarter of its thickness (where tall icons' tops sit), at any scale. `install_bar_corner_radius` seeds `corner-radius = 142` into `~/.config/omarchy/shell.toml` when absent.
- **Where:** `patches/0008-bar-clear-of-rounded-corners.patch`, `patches/KNOWN-TREES`, `lib/config-overlay.sh`, `tests/fold-omarchy-update-regressions.sh`.
- **Drop when:** upstream ships a corner or side-inset setting for the bar and the Fold uses it.

### A touch drag scrolls the app launcher

- **Kind:** 1, useful to anyone with a touchscreen (patch `0009`). **Upstream candidate.**
- **Bug:** a finger dragging over the app launcher (`shell/plugins/dock/AppGrid.qml`, the dock's app grid) never scrolled it: every cell set `preventStealing`, so the drag picked the app up and dropping it closed the launcher.
- **Fix:** patch `0009` sets `preventStealing` only for a mouse press (`event.source`), so touch drags scroll the grid. A touch picks an app up only after it is held still (`onPressAndHold`). Taps still launch, and mouse hover and drag are unchanged.
- **Where:** `patches/0009-touch-drag-scrolls-app-launcher.patch`, `patches/KNOWN-TREES`.
- **Drop when:** upstream lets a touch scroll the app grid.

### Home folder: ~/Projects exists, Go builds stay out of ~/go

- **Kind:** 1, useful to anyone. **Upstream candidate** (the `~/Projects` half; Omarchy's `bin/omarchy-provision-user` should `mkdir` Projects like `omarchy-upgrade-to-quattro` does).
- **Bug:** Files showed a "Projects" bookmark that opened "Unable to find" the Projects folder, because Omarchy 4.5.0 bookmarks it but never creates it. Separately, AUR Go packages built from source filled `~/go` (969 MB of module cache); stock Omarchy gets yay prebuilt.
- **Fix:** `lib/home-layout.sh` also creates `~/Projects`. `GOPATH` is `~/.cache/go` in `config/pacman/makepkg.conf` (yay's makepkg runs inherit it; a rerun of `container/install.sh` refreshes that block in an existing install) and for `fold-omarchy-update`'s `yay -Sua`. An existing `~/go` is left alone (it can hold personal files); delete its `pkg/mod` by hand to reclaim the space.
- **Where:** `lib/home-layout.sh`, `config/pacman/makepkg.conf`, `container/install.sh`, `container/bin/fold-omarchy-update`, `tests/home-layout-regressions.sh`.
- **Drop when:** upstream Omarchy creates `~/Projects` (first half); the `GOPATH` part stays unless upstream builds Go packages elsewhere.

### Seed Omarchy's one-time home files

- **Kind:** 1, useful to anyone running Omarchy from a git checkout. **Upstream candidate.**
- **Bug:** the Omarchy screensaver printed "Error reading input file" forever: `~/.config/omarchy/branding/` is made by the package (`/etc/skel`) and `omarchy-upgrade-to-quattro`, neither of which the fork runs.
- **Fix:** `omarchy_seed_home_defaults` creates the missing branding files, nautilus-python extensions, `~/Projects` with the GTK bookmarks and agent skill link, never overwriting, and fails if a copy fails; called by `container/install.sh` and `fold-omarchy-update`. Skipped: the quattro steps for XDG settings and flags.lua (already covered or harmless here) and its Limine, systemd `--user`, keyring and hardware steps.
- **Where:** `lib/omarchy-move.sh`, `container/install.sh`, `container/bin/fold-omarchy-update`, `tests/omarchy-packaged-helpers-regressions.sh`.
- **Drop when:** upstream ships an ARM package set (its `/etc/skel` seeds these).

### Audio runs in the container (PipeWire), not in Debian

- **Kind:** 1, useful to anyone. **Upstream candidate.**
- **Bug:** Debian's user PulseAudio crash-looped on the virtio-snd card and held `pulse/native`, while the
  Arch container had no `/dev/snd` and nothing started its PipeWire, so `pactl`/`wpctl` and Omarchy's
  volume keys, OSD and mixer had no sound server.
- **Fix:** the installer masks Debian's `pulseaudio.service`/`.socket`; `arch-hyprland` binds `/dev/snd`
  (only when it exists) with `DeviceAllow=char-alsa rw`, and the sound devices' group is mapped to the
  container user like the DRM/input ones; the new `audio-autostart` starts `pipewire`, `wireplumber` and
  `pipewire-pulse` at login (the container has no systemd to do it).
- **Where:** `host/install.sh`, `host/bin/arch-hyprland`, `container/bin/audio-autostart`,
  `lib/config-overlay.sh`, `config/hypr/autostart.lua`, `tests/installer-regressions.sh`,
  `tests/session-regressions.sh`.
- **Drop when:** upstream starts the audio stack in the container and binds the sound card itself.

## Quick checks

- `bash tests/run.sh --check patches`
- `bash tests/fold-omarchy-update-regressions.sh`; `bash tests/omarchy-packaged-helpers-regressions.sh`
- `bash tests/omarchy-app-icons-regressions.sh`
- `bash tests/fold-drawer-regressions.sh`
- `bash tests/fold-hyprgrass-build-regressions.sh`; `bash tests/installer-regressions.sh`
- `luac -p config/hypr/*.lua`
- `bash tests/home-layout-regressions.sh`
- `python3 -B tests/tool-programs-regressions.py`
- `python3 -B tests/desktop-extras-regressions.py`

## Known failures on the base commit

- `python3 -B tests/desktop-tweaks-regressions.py` fails with `ValueError: substring not found`
  (`preset.index('schema: rime_ice')`), also on the commit before this fork change.
