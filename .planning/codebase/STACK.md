# Stack

Omarchy is not an application — it is a **system configuration package** for an
Arch Linux + Hyprland distribution. The repo builds into Arch packages whose
payloads are bash commands, a Quickshell (QML) desktop shell, Hyprland Lua
configs, themes, and install/migration scripts.

## Languages & runtimes

| Language | Where | Notes |
|---|---|---|
| Bash 5 | `bin/` (454 `omarchy-*` scripts + `omarchy` router), `install/`, `migrations/`, `test/` | Style enforced by `AGENTS.md`: `#!/bin/bash` shebang, `[[ ]]` / `(( ))` conditionals. Scripts under `install/` and `migrations/` are sourced and omit shebangs. |
| QML + JavaScript | `shell/` (~104 `.qml`, ~28 `.js`) | Runs inside one long-running [Quickshell](https://quickshell.org/) process (Qt6/QML engine). Entry: `shell/shell.qml` (`ShellRoot`). `*Model.js` files are plain JS, deliberately Node-loadable for tests (see `docs/menu.md`, `docs/notifications.md`). |
| Lua | `config/hypr/*.lua`, `default/hypr/**` (~75 `.lua` repo-wide) | Hyprland's Lua config API (`hl.*`, `require("default.hypr.*")`). User config `config/hypr/hyprland.lua` loads `default/hypr/omarchy.lua` then user overlay files. `.luarc.json` at root configures the Lua LSP. |
| TOML | `themes/*/colors.toml`, `shell.toml`, various app configs | Theme palettes and shell design tokens. |
| JSON / JSONC | `shell/plugins/**/manifest.json`, `config/omarchy/shell.json`, `default/omarchy/omarchy-menu.jsonc` | Plugin manifests, shell layout state, menu definition (JSON-with-`//`-line-comments only, per `docs/menu.md`). |
| Node.js | `test/shell.d/base-test.sh` (`require_command node`, JS piped to `node`) | Test helper runtime for exercising shell `Model.js` logic headlessly. |

## Key system dependencies

Shipped by the ISO package lists `install/omarchy-base.packages` (~150 pkgs)
and `install/omarchy-other.packages` (~70 pkgs). Highlights:

- **Compositor/session**: `hyprland`, `hyprland-guiutils`, `hyprsunset`,
  `uwsm` (session manager; launches `hyprland.desktop` via
  `default/wayland-sessions/omarchy.desktop`), SDDM login.
- **Shell**: `quickshell` (`qs` binary; IPC via `qs ipc`), plus Quickshell
  service modules used by QML: `Quickshell.Hyprland`, `.Wayland`,
  `.Services.{Pipewire,UPower,Mpris,SystemTray,Polkit,Pam,Notifications}`,
  `.Bluetooth`, `.Networking`, `.Io`.
- **CLI surface**: `gum` (43 scripts), `jq`, `fzf`, `pacman`/`yay`, `systemctl`,
  `nmcli`, `bluetoothctl`, `ddcutil`, `brightnessctl`, `wpctl`, `wl-copy`/`wl-paste`,
  `playerctl`, `snapper`, `mise`, `inotify-tools`, `systemd-cat`/`systemd-inhibit`.
- **User-facing stack**: foot/kitty/alacritty/ghostty terminals, Neovim
  (`omarchy-nvim` package), Chromium, btop, lazygit, Docker, fcitx5,
  gnome-keyring, Nautilus, LibreOffice.

## Packaging & installation layout

Two Arch packages are built from this one repo; **PKGBUILDs live in the
separate `omarchy-pkgs` repo** (`pkgbuilds/`); `omarchy-keyring` and
`omarchy-nvim` are sibling packages there. See `docs/file-layout.md` for the
authoritative map.

| Repo tree | Package | Installs to |
|---|---|---|
| `bin/omarchy-*` | `omarchy` | `/usr/bin/omarchy-*` (+ symlinks under `/usr/share/omarchy/bin/`) |
| `install/`, `migrations/`, `themes/`, `shell/`, `version` | `omarchy` | `/usr/share/omarchy/{install,migrations,themes,shell,version}` |
| `config/` | `omarchy-settings` | `/etc/skel/.config/**` (seed) + `/usr/share/omarchy/config/` (resync source) |
| `default/`, `etc/`, `applications/`, logos | `omarchy-settings` | `/usr/share/omarchy/default/`, `/etc/**`, `/usr/lib/systemd/`, `/usr/share/{fonts,plymouth,sddm,...}` etc. |
| `manual/`, `docs/`, `agents/`, `test/`, `plans/` | — | repo only, never packaged |

`$OMARCHY_PATH` is the single runtime anchor (normally `/usr/share/omarchy`),
set by `default/bash/env-bootstrap`, which is sourced from
`/etc/profile.d/omarchy.sh`, `/etc/skel/.bashrc`, uwsm `env.d`, and the bash
rc chain. Some `/etc` files owned by upstream Arch packages ship as
`/usr/share/omarchy/etc-overrides/` and are `cp -f`'d by package scriptlets.

## Version & channels

`version` file: `4.0.0.alpha`. Channels `stable|rc|edge|dev` managed by
`omarchy-channel-set`; `omarchy-version` derives the version from `pacman -Q`
(or `dev (<hash>)` for a linked checkout).

## Development workflow

- `omarchy dev link <checkout>` (`bin/omarchy-dev-link`) writes
  `/etc/omarchy.conf` so `OMARCHY_PATH` resolves to the working tree after
  reboot, plus a `sudoers.d` drop-in so `sudo omarchy-*` also resolves there.
  Covers `$OMARCHY_PATH`-resolved trees only (`bin/`, `default/`, `shell/`,
  `themes/`, `config/`).
- `omarchy dev pkg-test` (`bin/omarchy-dev-pkg-test`) builds/installs real
  packages from a checkout for changes at fixed system paths (`/etc`,
  `/usr/lib/systemd`, udev, plymouth) that dev-link cannot shadow.
- `omarchy dev unlink` restores the packaged path.

## Testing

- `./test/all` → `test/cli` (one 714-line script: router, metadata lint,
  theme pipeline with stub binaries) + `test/shell` (every
  `test/shell.d/*-test.sh`, 236 suites, TAP-flavored via `base-test.sh`).
- `./test/acceptance` — graphical suite run inside a live session in a
  disposable VM; intentionally excluded from `test/all`.
- `omarchy dev benchmark cli` tracks router dispatch latency.
