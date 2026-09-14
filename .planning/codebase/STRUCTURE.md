# Structure

Repo root: `/home/buttercup/repos/omarchy` (fork of omacom/omarchy).
One-line purpose per tree; install destinations per `docs/file-layout.md`.

## Top level

| Path | Purpose |
|---|---|
| `bin/` | `omarchy` router + 454 `omarchy-*` bash commands → `/usr/bin/omarchy-*`. Every executable is a command; filename = default route. |
| `shell/` | Quickshell (QML) desktop — the `omarchy-shell` process → `/usr/share/omarchy/shell/`. Entry: `shell/shell.qml`; docs: `shell/README.md`. |
| `config/` | Default user configs → `/etc/skel/.config/**` + `/usr/share/omarchy/config/`. Hyprland Lua (`config/hypr/`), terminals, `omarchy/shell.json`, `omarchy/hooks/*.d/` samples, `omarchy/extensions/omarchy-menu.jsonc`. |
| `default/` | Package-owned defaults → `/usr/share/omarchy/default/` + scattered system paths: `hypr/` Lua modules (bootstrap, omarchy, bindings/, apps/, toggles/), `bash/` (env-bootstrap, rc chain), `themed/*.tpl` theme templates, `systemd/` units, `uwsm/env.d`, `limine/`, `snapper/`, `sddm/`, `plymouth/`, `fonts/omarchy/omarchy.ttf` (icon font), `libalpm/hooks/`, `omarchy/omarchy-menu.jsonc`, `audio/tunings/`, `applications/mimeapps.list`. |
| `etc/` | `/etc/**` drop-ins owned outright: mkinitcpio, NetworkManager, sudoers.d, sysctl.d, systemd logind/oomd/resolved, profile.d, limine-entry-tool.d, xdg, cups, plymouth, faillock. (Upstream-owned files ship via `etc-overrides/` instead.) |
| `applications/` | Web-app `.desktop` files + `icons/` → `/etc/skel/.local/share/applications/` and hicolor icon dirs. |
| `themes/` | 22 first-party themes (`<name>/colors.toml`, optional `shell.toml`/`shell.lock.toml`, `backgrounds/`, `preview*.png`, `unlock.png`, `icons.theme`, `keyboard.rgb`, `neovim.lua`, `vscode.json`; `light.mode` marker supported per `docs/theming.md`) → `/usr/share/omarchy/themes/`. |
| `install/` | ISO/chroot install scripts: `omarchy-base.packages` + `omarchy-other.packages` (pacstrap lists), `config/`, `hardware/` (vendor quirks), `login/` (SDDM), `post-install/`, `provisioning/` (owner-creation systemd units), `user/` incl. `user/first-run/` (units, hooks, toasts), `helpers/`. Sourced, no shebangs. |
| `migrations/` | 114 `<epoch>.sh` per-user migrations run by `omarchy-migrate`; state in `~/.local/state/omarchy/migrations/`. |
| `test/` | `all` / `cli` / `shell` / `acceptance` runner scripts + `shell.d/` (236 `*-test.sh` suites + `base-test.sh`, `fixtures/`, `qml-text-format-scan.py`) + `acceptance.d/` (8 VM suites + `base-test.sh`). |
| `docs/` | Internal architecture reference: `file-layout.md` (repo→install map), `omarchy-shell.md`, `cli-router.md`, `update-process.md`, `theming.md`, `menu.md`, `notifications.md`, `audio-tuning.md`, `testing.md`. |
| `agents/skills/` | Contributor task guides: command-metadata, install-scripts, shell-dev, icon-font, acceptance-tests, visual-verification, migrations. |
| `manual/` | 51 published end-user chapters + `images/`; mirrored to learn.omacom.io. Never codebase internals. |
| `plans/` | Design docs: `backup.md`, `dots.md`, `remote.md`, `server.md`, `images/`. |
| `AGENTS.md` / `CLAUDE.md` | Contributor rules (style, naming, helpers, tests); CLAUDE.md just includes AGENTS.md. |
| `version` | `4.0.0.alpha` — packaged at `/usr/share/omarchy/version`. |

## shell/ internals

```
shell/
  shell.qml            # ShellRoot: shared singletons, plugin loading, IPC targets
  Commons/             # qs.Commons: Color.qml, Style.qml, Border.qml, Util.qml, BorderGeometry.js
  Ui/                  # qs.Ui: ~35 shared widgets (Panel, Dropdown, Toggle, BorderSurface, ...)
  services/            # PluginRegistry.qml, BarWidgetRegistry.qml, AppLibrary.qml,
                       # Plugin*Api.qml facades, AuthServiceStore.js, hidden-entries.sh
  plugins/             # first-party plugins (manifest.json each)
```

`shell/plugins/` layout (each dir = one plugin, id `omarchy.*`):

- `bar/` — `omarchy.bar`, the built-in full bar: `Bar.qml`, `BarModel.js`,
  `widgets/` (ActiveWindow, Indicators, KeyboardLayout, Microphone, Spacer,
  SystemUpdate, Tray, Workspaces — each `Name.qml` + `Name.manifest.json`),
  `indicators/` (Dnd, Dictation, NightLight, Reminder, ScreenRecording,
  StayAwake).
- `panels/` — summonable bar-widget/panel plugins: `audio`, `bluetooth`,
  `clock`, `disk-speedtest`, `dropbox`, `monitor`, `network`, `power`,
  `speedtest`, `tailscale`, `weather`, `wifiqr`.
- `services/` — headless singletons: `battery`, `idle` (screensaver/lock
  timings), `media` (MPRIS), `nightlight`.
- Top-level plugins: `menu` (the Omarchy menu), `notifications` (the
  freedesktop daemon), `lock` (session lock, `authentication` capability),
  `osd`, `background`, `clipboard`, `emojis`, `image-picker`, `polkit`,
  `agents`, `reminders`, `dev-gallery`.

Third-party plugins never live here — they are git clones under
`~/.config/omarchy/plugins/<id>/` on user machines.

## test/ internals

- `test/all` — aggregate runner for `cli` + `shell` (not acceptance).
- `test/cli` — single script: router dispatch, `--help` interception,
  metadata lint (`omarchy commands --check`), theme pipeline with stub
  binaries and fake `$HOME`.
- `test/shell.d/` — one `*-test.sh` per area; source `base-test.sh` for
  `ROOT` discovery, TAP `pass`/`fail`, `require_command`, Node helpers for
  `Model.js` files. New tests: drop `test/shell.d/<area>-test.sh`.
- `test/acceptance` + `acceptance.d/` — in-guest suites run over SSH into a
  live Omarchy VM (built by `omarchy-iso-test`); artifacts in
  `$OMARCHY_ACCEPTANCE_DIR`. See `agents/skills/acceptance-tests.md`.

## Key file anchors

| File | Why it matters |
|---|---|
| `bin/omarchy` | Router + `GROUP_DESCRIPTIONS` (lines 29–97) |
| `bin/omarchy-shell` | IPC forwarder into the running shell |
| `bin/omarchy-launch-shell` / `omarchy-restart-shell` | Shell lifecycle |
| `bin/omarchy-theme-set` + `omarchy-theme-set-templates` | Theme pipeline |
| `bin/omarchy-update` / `omarchy-migrate` / `omarchy-hook` | Update, migrations, user hooks |
| `bin/omarchy-dev-link` / `omarchy-dev-pkg-test` | Dev workflow (`/etc/omarchy.conf`) |
| `bin/omarchy-refresh-config` / `omarchy-reinstall-configs` | Default→user config sync |
| `bin/omarchy-plugin-*` / `bin/omarchy-bar` | Plugin/bar management |
| `shell/services/PluginRegistry.qml` | Plugin manifest schema + enabled-state source of truth |
| `config/omarchy/shell.json` | Shipped default bar layout / idle timings |
| `default/omarchy/omarchy-menu.jsonc` | Menu definition (schema: `docs/menu.md`) |
| `default/bash/env-bootstrap` | `OMARCHY_PATH` + PATH single source of truth |
| `default/libalpm/hooks/` | ALPM update guard + Hyprland reload pause/resume |
| `install/omarchy-*.packages` | ISO package manifests |
