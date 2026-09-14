# Integrations

External systems and interfaces this codebase talks to, grouped by direction.

## Hyprland (compositor)

- **IPC**: `hyprctl` is called from ~53 `bin/` scripts — monitor queries
  (`omarchy-hyprland-monitor-*`), window focus (`omarchy-hyprland-focus-app`),
  input device toggles, `hyprctl reload` guards during package upgrades.
  `HYPRLAND_INSTANCE_SIGNATURE` is recovered from
  `$XDG_RUNTIME_DIR/hypr/<sig>` when callers run outside the session
  (e.g. `bin/omarchy-restart-shell`).
- **Config**: Hyprland loads Lua. `config/hypr/hyprland.lua` (seeded to
  `~/.config/hypr/`) `require`s `default.hypr.omarchy`, which pulls
  `default/hypr/{bindings,envs,input,looknfeel,windows,autostart,...}.lua`;
  themes inject `omarchy.current.theme.hyprland` via
  `default/hypr/require_optional.lua`.
- **Autostart**: `default/hypr/autostart.lua` runs
  `hl.exec_cmd("omarchy-launch-shell")` — the shell's only entry point.
- **QML**: `import Quickshell.Hyprland` in shell plugins (workspaces,
  active window, monitors).

## Quickshell IPC (`omarchy-shell`)

The running shell is reachable via `qs ipc -n -p "$OMARCHY_PATH/shell" call
-- <target> <method> [args]`, wrapped by `bin/omarchy-shell` (adds WAYLAND
discovery, timeouts via `OMARCHY_SHELL_IPC_TIMEOUT`, `-q` quiet mode).

- Host targets (`shell/shell.qml`): `shell` (ping, summon/hide/toggle/call,
  rescanPlugins, reloadConfig, applyTheme, setPluginEnabled, put/move/set
  BarWidget, listPlugins, …) and `image-selector` (open/preload/cancel).
- Plugin-registered targets named by plugin id: `background`, `osd`, `media`,
  `notifications`, `lock`, `omarchy.clock`, `omarchy.network`, etc.
  (`IpcHandler { target: root.ipcTarget }` throughout `shell/plugins/`).
- CLI wrappers build on it: `bin/omarchy-menu` (toggle/summon/close the
  `omarchy.menu` plugin), `bin/omarchy-bar`, `omarchy-plugin-*`,
  `bin/omarchy-theme-set` (pushes `shell applyTheme <colorsB64> <shellB64>`
  and `background themeTransition`).

## Package management (pacman / AUR / ALPM)

- Helpers: `omarchy-pkg-add` / `omarchy-pkg-drop` (the blessed wrappers —
  use these, not raw `pacman -R*`), `omarchy-pkg-missing`/`present`,
  `omarchy-update-aur-pkgs` (`yay -Sua`).
- **ALPM hooks** shipped via `default/libalpm/hooks/` →
  `/usr/share/libalpm/hooks/`:
  - `00-omarchy-update-guard.hook` → `bin/omarchy-update-pacman-guard`
    aborts direct `pacman -Syu` unless `OMARCHY_UPDATE_PACMAN=1`
    (Omarchy-owned flows) or `OMARCHY_ALLOW_DIRECT_PACMAN=1` (explicit bypass).
  - `10/90-omarchy-hyprland-reload-{pause,resume}.hook` → disable live
    Hyprland reloads while `/usr/share/omarchy/default/hypr/**` is replaced.
- Update pipeline: `bin/omarchy-update` orchestrates lock → free-space →
  snapper snapshot → stay-awake → `pacman -Syu` → `omarchy-migrate` →
  `omarchy-hook post-update` → restart checks (see `docs/update-process.md`).

## systemd

- **User units** shipped via `default/systemd/user/` → `/usr/lib/systemd/user/`:
  `omarchy-migrate-notify.service` (post-`graphical-session.target` login
  prompt), `omarchy-sleep-lock`, `omarchy-crash-watch`, `omarchy-fcitx5`,
  `omarchy-recover-internal-monitor`, `omarchy-speaker-tuning`,
  `bt-agent`, `omarchy-tailscale-receive`. Enabled by
  `install/user/first-run/enable-user-units.sh`.
- **System integration**: `systemd/system-sleep/` hooks, `systemd/logind.conf.d`,
  `oomd`, `zram-generator`, `plocate-updatedb` drop-in, provisioning units in
  `install/provisioning/` (`omarchy-provision-owner.service`, factory-reset
  finish).
- Shell logging: `bin/omarchy-launch-shell` runs Quickshell under
  `systemd-cat -t omarchy-shell` so logs survive in the journal.
- Sleep inhibition during updates: `systemd-inhibit` via
  `bin/omarchy-update-stay-awake`.
- Session env read: `systemctl --user show-environment` for `OMARCHY_PATH`.

## Notifications

The shell **is** the notification daemon —
`shell/plugins/notifications/Service.qml` hosts a Quickshell
`NotificationServer` claiming `org.freedesktop.Notifications` (no dunst/mako).
Senders: `bin/omarchy-notification-send` (the required wrapper; ~47 scripts
use it — never call `notify-send` directly), any libnotify app. State mirrors
to `~/.local/state/omarchy/notifications/` (live JSON files + `history/` +
`images/`); see `docs/notifications.md`.

## Hardware & desktop services

- **Brightness**: `brightnessctl` (internal panels, keyboard);
  `ddcutil` DDC/CI for external monitors in `bin/omarchy-brightness-display-ddc`
  (I2C bus ↔ DRM connector mapping cached under `$XDG_RUNTIME_DIR`).
- **Network**: NetworkManager `nmcli` (`omarchy-network-*`, `omarchy-wifi-*`,
  panels/network plugin via `Quickshell.Networking`), `nm-online` wait in
  first-run, `omarchy-dns` (resolved drop-ins + sudoers).
- **Bluetooth**: `bluetoothctl`/`bluetoothd` via `Quickshell.Bluetooth`,
  `omarchy-bluetooth-*`, `bt-agent.service`.
- **Audio**: PipeWire/WirePlumber — `wpctl` in `omarchy-audio-*`,
  `Quickshell.Services.Pipewire` in the audio panel; vendor speaker tunings
  are PipeWire filter-chains run as a separate client service
  (`docs/audio-tuning.md`).
- **Media**: MPRIS via `Quickshell.Services.Mpris` (+ `playerctl` fallback in
  `MediaModel.js`) — `omarchy.media` service.
- **Battery/power**: `Quickshell.Services.UPower`, `powerprofilesctl`,
  `omarchy-battery-*`, `omarchy-powerprofiles-*`.
- **Other Quickshell services**: `SystemTray` (tray widget), `Polkit`
  (authentication agent plugin `omarchy.polkit`), `Pam` (lock plugin —
  `omarchy.lock` carries the `authentication` capability).
- **Clipboard**: `wl-copy`/`wl-paste` (`omarchy-clipboard-*`,
  `omarchy-menu-share` uses `wl-paste` + LocalSend).
- **Screenshots/recording**: `grim`, `slurp`, `gpu-screen-recorder`,
  `hyprland-preview-share-picker`.

## Themes

`omarchy-theme-set <name>` (`bin/omarchy-theme-set`) stages
`~/.local/state/omarchy/current/next-theme` from `$OMARCHY_PATH/themes/<name>`
+ `~/.config/omarchy/themes/<name>` overlay, renders `default/themed/*.tpl`
via `bin/omarchy-theme-set-templates` (awk-based `{{ var }}` substitution +
color helpers), atomically swaps into `current/theme`, then pushes colors to
the running shell over IPC and retints apps in parallel
(`post_theme_commands` list). `omarchy-theme-install` git-clones third-party
themes into `~/.config/omarchy/themes/`; repo-sourced themes are denied
`.lua`, terminal configs, and `vscode.json` (`INSTALLED_THEME_DENIED`).
Details: `docs/theming.md`.

## Shell plugins (third-party code loading)

`omarchy plugin add <git-url>` (`bin/omarchy-plugin-add`) clones into
`~/.config/omarchy/plugins/<id>/` (guarded by `omarchy-git-url-check`),
`omarchy plugin update` fast-forwards, file saves trigger hot-reload
(`rescanPlugins`). Plugins are unsandboxed QML in the shell process; see
`docs/omarchy-shell.md` and `shell/README.md`.

## Session/environment plumbing

- **uwsm**: session wrapper; env via `/usr/share/uwsm/env.d/10-omarchy`
  (`default/uwsm/`) → sources `default/bash/env-bootstrap`.
- **PAM**: lock plugin uses PAM password + fingerprint flows; sudoers drop-ins
  under `etc/sudoers.d/`; `omarchy-dev-link` adds `secure_path` for dev bins.
- **Snapshots/boot**: `snapper` (`omarchy-snapshot`, pre-update snapshots),
  `limine` bootloader (`default/limine/`, `omarchy-refresh-limine`),
  `mkinitcpio` drop-ins, `plymouth` theme, `sddm` theme.
- **Misc CLIs**: `tailscale`, `dropbox`, `mise` (tool versioning, updated in
  the blessed path), `xdg-settings`/`xdg-mime` (default apps),
  `fcitx5` (IME), `gnome-keyring`/`secret-tool`, `fwupd` (firmware),
  `docker`, `plocate`, `cups`, `gum`/`fzf` for interactive UI.
