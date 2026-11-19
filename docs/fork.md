# Fork inventory

Fork of rwanglq-ctrl/omarchy-xiaomi18fold (remote `upstream`). One entry per line: change | where | kind | hook lines in upstream files.

Kinds: 1 = useful to anyone (upstream candidate), 2 = user preference over upstream, 3 = machine-specific.

- hyprgrass build | `container/bin/fold-hyprgrass-build` (new file) | 3 (phone) | `container/install.sh`: `fold-hyprgrass-build` in the helper install list, a `build_hyprgrass` step and its `hyprgrass` report entry; `packages/repo-full.txt`: `glm`, `nwg-drawer` (the 3/4-finger-down gesture runs fold-drawer); `config/hypr/touch.lua`: header comment. Upstream candidate: the script, since touch gestures never worked without it.

## Quick checks

- `bash -n` and `shellcheck -S warning -s bash` on `container/bin/fold-hyprgrass-build` and `container/install.sh`; `bash tests/installer-regressions.sh`, `bash tests/fold-hyprgrass-build-regressions.sh`.
