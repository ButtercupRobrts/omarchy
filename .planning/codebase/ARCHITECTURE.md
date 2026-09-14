# Architecture

Omarchy is a system-configuration package, not an app: the repo builds two
Arch packages (`omarchy`, `omarchy-settings`; PKGBUILDs in the separate
`omarchy-pkgs` repo) whose contents are bash commands, a Quickshell desktop,
Hyprland Lua config, themes, and install/migration scripts. The authoritative
deep-dives live in `docs/` — this is the map.

## The `omarchy` CLI router

`bin/omarchy` (~1100 lines of bash) maps spaced commands onto the flat
`bin/omarchy-*` namespace: `omarchy theme set foo` → `exec omarchy-theme-set foo`.

- **No registry to maintain**: every executable `bin/omarchy-*` is a command;
  filename is the default route (`omarchy-theme-set` → group `theme`, name
  `set`). Metadata in the comment header (`# omarchy:summary=`,
  `group|name|args|examples|alias|requires-sudo|hidden`) refines routing and
  help. See `docs/cli-router.md`, `agents/skills/command-metadata.md`.
- **Two-pass dispatch**: fast path probes filenames by joining args with
  hyphens (hot path, no header parsing); fallback loads all metadata for
  metadata-moved routes and aliases. `--help` anywhere in leftovers intercepts.
- **Groups** are prefixes (`theme-`, `update-`, `refresh-`, `hw-`,
  `restart-`, `launch-`, `toggle-`, `pkg-`, `capture-`, …). The browsable
  group list is the hand-curated `GROUP_DESCRIPTIONS` table in `bin/omarchy`
  (lines 29–97) — update it when adding a user-facing group. `apply-` and
  `provision-` are deliberately absent (hidden install plumbing that still
  routes).
- `omarchy commands --check` is the metadata lint run by `test/cli`.

## omarchy-shell: one process for the whole desktop

A single long-running Quickshell instance hosts bar, panels, overlays, menus,
and headless services as **plugins** (`shell/README.md`, `docs/omarchy-shell.md`).

- **Launch**: `default/hypr/autostart.lua` → `hl.exec_cmd("omarchy-launch-shell")`
  → `bin/omarchy-launch-shell` runs `quickshell -n -p "$OMARCHY_PATH/shell"`
  under `systemd-cat`, with `QS_DISABLE_FILE_WATCHER=1` (package upgrades
  must not hot-reload a half-written tree; `omarchy-restart-shell` restarts
  deliberately and refuses while the session is securely locked).
- **Entry**: `shell/shell.qml` (`ShellRoot`) owns the shared singletons —
  `PluginRegistry`, `BarWidgetRegistry`, `AppLibrary` — and injects them into
  plugins as properties. `shell/Commons` (`qs.Commons`: Color, Style, Border,
  Util) and `shell/Ui` (`qs.Ui`: ~35 shared widgets) are the design system.
- **Config**: `~/.config/omarchy/shell.json` is canonical once it exists
  (no deep-merge); `config/omarchy/shell.json` ships defaults, and a bundled
  fallback is compiled into `shell.qml`. Layout = `bar.layout.<section>[]`
  entries for widgets + `plugins[]` for everything else; settings are inline.
- **Theme**: `Color`/`Style`/`Border` singletons load `colors.toml` +
  `shell.toml` pushed over IPC (`shell applyTheme`); a user
  `~/.config/omarchy/shell.toml` is watched and wins over the theme's.

## Plugin contract

A plugin is a directory with `manifest.json` (schema in
`shell/services/PluginRegistry.qml`):

```json
{ "schemaVersion": 1, "id": "omarchy.clock", "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" }, "keepLoaded": true }
```

- **Kinds**: `bar-widget`, `bar` (full-bar replacement; only one active,
  falls back to `omarchy.bar`), `panel`, `overlay`, `menu`, `service`
  (headless singleton). Multi-kind manifests are normal
  (`omarchy.menu` is `menu` + `bar-widget`).
- **Discovery**: first-party from `$OMARCHY_PATH/shell/plugins/` (load by
  default; disabling records `disabledPlugins[]`); third-party from
  `~/.config/omarchy/plugins/<id>/` (git clones via `omarchy plugin add`;
  enabled ⇔ id present in shell.json).
- **Injection**: entry points declare `omarchyPath`, `shell`, `manifest`,
  `pluginRegistry`, `barWidgetRegistry` props. First-party gets trusted host
  objects; third-party gets **capability-scoped facades** (`PluginShellApi`,
  `PluginRegistryApi`, `PluginBarStateApi`, `PluginAppLibraryApi`,
  `PluginFirstPartyServiceApi` in `shell/services/`). Authentication services
  (`omarchy.lock`, manifest `omarchy.capabilities: ["authentication"]`) stay
  out of the public service map. Facades are API boundaries, not sandbox —
  visual plugins share the QML scene graph.
- **IPC**: host targets `shell` + `image-selector`; each plugin may register
  an `IpcHandler` target named for its id (`omarchy-shell lock status`,
  `omarchy-shell osd ...`). `bin/omarchy-shell` is the CLI forwarder.
- **Lifecycle**: panels/overlays/menus load on summon; `keepLoaded: true`
  survives between summons and across hot-reload (required for `omarchy.lock`
  so Hyprland never loses the lock client). Saving files under
  `~/.config/omarchy/plugins/` auto-reloads.
- **Built-in hacking path**: `omarchy plugin clone omarchy.clock` →
  `~/.config/omarchy/plugins/<user>.clock` with IPC identity preserved.
  Planners: edit first-party plugins in the repo; users clone to override.

## Config layering

```
repo config/** ──► /etc/skel/.config/** (seed at useradd -m)
              ──► /usr/share/omarchy/config/** (resync source)
repo default/** ─► /usr/share/omarchy/default/** + assorted system paths
user            ─► ~/.config/** (live user files)
```

- `/etc/skel` only fires at user creation; `omarchy-refresh-config <path>`
  copies a shipped default over `~/.config/<path>` with a timestamped `.bak`;
  `omarchy-reinstall-configs` is the destructive full resync.
- `~/.local/state/omarchy/` holds generated state: `current/theme`,
  `current/background` symlink, `migrations/` markers, `done/` completion
  markers (`omarchy-done`), `restart-*-required` markers,
  `notifications/` mirror.
- `$OMARCHY_PATH` (`default/bash/env-bootstrap` → profile.d, skel bashrc,
  uwsm env.d, SSH envs) is the single source of truth for the active tree;
  `/etc/omarchy.conf` (written by `omarchy dev link`) overrides it to a dev
  checkout.

## Themes

`themes/<name>/` ships `colors.toml` + optional `shell.toml`, `backgrounds/`,
previews, per-app files. `omarchy-theme-set` stages into
`~/.local/state/omarchy/current/next-theme`, renders `default/themed/*.tpl`
templates (`{{ var }}` placeholders filled from colors.toml), swaps
`current/theme` atomically, pushes the palette to the shell over IPC, retints
running apps in parallel (`post_theme_commands` in `bin/omarchy-theme-set`),
then fires the `theme-set` hook. User themes overlay from
`~/.config/omarchy/themes/`; git-installed themes are filtered
(no `.lua`/terminal configs/`vscode.json`). See `docs/theming.md`.

## Hooks

`bin/omarchy-hook <name>` runs `~/.config/omarchy/hooks/<name>` then every
file in `<name>.d/` (skipping `*.sample`). Shipped hook points:
`theme-set`, `post-update`, `post-boot`, `font-set`, `battery-low`,
`pre-refresh-pacman` (samples in `config/omarchy/hooks/`). Installed hooks
ship in `install/user/first-run/*.hook` and are wired by
`omarchy-hook-install`.

## Migrations

`migrations/<epoch>.sh` (114 files), run **per-user** by `bin/omarchy-migrate`
after pacman inside `omarchy update`. Must be idempotent; completion markers
in `~/.local/state/omarchy/migrations/`. Users who bypass `omarchy update`
are caught at next login by `omarchy-migrate-notify.service`. Authoring:
`agents/skills/migrations.md`.

## Update pipeline

`bin/omarchy-update` owns the blessed flow (`docs/update-process.md`):
transcript → per-user lock (`$XDG_RUNTIME_DIR/omarchy-update.lock`) →
free-space check → cache prune → snapper snapshot → sleep inhibitor →
dev-link fast-forward / keyring / `pacman -Syu` (through the ALPM guard's
`OMARCHY_UPDATE_PACMAN=1`) → AUR/mise → `omarchy-migrate` →
`omarchy-hook post-update` → restart checks (always restarts the shell).
Direct `pacman -Syu` is aborted by the ALPM pre-transaction guard.

## Install/provisioning flow (ISO)

`omarchy-apply-system` (root, in chroot) sources `install/config|hardware|
login|post-install/all.sh`; `install/*.packages` are the pacstrap lists.
Per-user: `omarchy-provision-user` (finalize once; marker
`done/finalize-user`) then `omarchy-provision-first-run` on first graphical
login (user units, GNOME/GTK settings, welcome/wifi toasts; marker
`done/first-run-user`). Deferred provisioning via
`install/provisioning/omarchy-provision-owner.service`. Details:
`docs/file-layout.md`.

## Where to edit what (planner's safety note)

`/usr/share/omarchy` is **installed-package territory** — never edit in
place. Edit this repo, then either `omarchy dev link` (covers
`$OMARCHY_PATH`-resolved trees: bin, default, shell, themes, config) or
`omarchy dev pkg-test` (required for fixed paths: `/etc`, systemd units,
udev). Shell plugin experimentation by end users happens in clones under
`~/.config/omarchy/plugins/`; first-party plugin source lives in
`shell/plugins/` here.
