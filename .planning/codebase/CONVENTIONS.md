# Conventions

How Omarchy code is actually written. `AGENTS.md` is the codified style guide;
task-specific procedure lives in `agents/skills/*.md` (command-metadata,
install-scripts, shell-dev, migrations, acceptance-tests, visual-verification,
icon-font). Everything below was verified against the tree.

## Bash (bin/, test/, install/, migrations/)

- **Shebangs**: `#!/bin/bash`, never `#!/usr/bin/env bash` (`bin/omarchy:1`,
  `bin/omarchy-cmd-missing:1`). A handful of `bin/` commands are Python and use
  `#!/usr/bin/python3` (`bin/omarchy-agent-usage-claude:1`,
  `bin/omarchy-dev-font:1`); they still carry the same `# omarchy:` metadata
  comments. Scripts under `install/` and `migrations/` are sourced/run via
  `bash -euo pipefail` and intentionally omit shebangs
  (`agents/skills/install-scripts.md:11`, `migrations/1781158082.sh`).
- **Indentation**: two spaces, no tabs — consistent across every sampled file.
- **Conditionals**: `[[ ]]` for string/file tests, `(( ))` for numerics.
  Verified: `(( ${#failed[@]} > 0 ))` (`test/all`), `(( EUID == 0 ))`
  (`bin/omarchy-pkg-add`), `(( attempt < 3 ))`
  (`test/shell.d/base-test.sh:58`), `[[ $socket == /* ]]`
  (`base-test.sh:42`). Variables are unquoted inside `[[ ]]`; string literals
  are quoted when comparing (`[[ $1 == "-q" ]]`, `bin/omarchy-shell`).
- **set flags**: not uniform. `set -euo pipefail` in most substantial scripts
  (`bin/omarchy-notification-send:5`, every `test/shell.d/*-test.sh`); the
  router uses only `set -o pipefail` (`bin/omarchy:3`); trivial guards like
  `bin/omarchy-cmd-missing` omit `set` entirely. Match the file's weight.
- **Functions**: lowercase snake_case (`fail`, `usage`,
  `parse_omarchy_option` in `bin/omarchy-notification-send`), `local` for
  function vars. Constants/flags are UPPERCASE at the top
  (`QUIET=0` in `bin/omarchy-shell`, `ON_TEMP=4000` in
  `bin/omarchy-toggle-nightlight`).
- **Usage text**: heredoc `USAGE` blocks printed on missing args
  (`bin/omarchy-refresh-config`, `bin/omarchy-shell`). Errors go to stderr,
  often with ANSI red (`\e[31m` in `omarchy-refresh-config`, `\033[31m` in
  `omarchy-pkg-add`).
- **Helpers over raw commands**: use `omarchy-cmd-missing`/`omarchy-pkg-add`/
  `omarchy-notification-send` etc. instead of `command -v`, raw `pacman`, or
  `notify-send` — enforced by `test/shell.d/bin-style-test.sh`. Exceptions:
  migrations, package-helper internals, and pre-default-package-set code
  (`AGENTS.md` "Helper Commands", `agents/skills/install-scripts.md:18`).

## Command metadata (bin/)

- Declared as comments in the first 80 lines (`METADATA_SCAN_LIMIT=80`,
  `bin/omarchy:5`). Keys: `group`, `name`, `summary`, `args`, `examples`
  (` | `-separated), `alias`/`aliases`, `hidden=true`, `requires-sudo=true`
  (`agents/skills/command-metadata.md`). Example block at
  `bin/omarchy-notification-send:3-5`.
- `test/cli` lints every `bin/` executable: `summary` required, no
  `omarchy:binary=`, no empty `args=`, removed fields (`legacy`, `usage`,
  `visibility`, `mutates`, `interactive`) rejected, no `requires-sudo=false`
  (`test/cli:606-611`).

## Command naming

- All commands are `bin/omarchy-<group>-<name>` in kebab-case. The group
  prefix drives routing; the authoritative user-facing group list is
  `GROUP_DESCRIPTIONS` in `bin/omarchy:29+` (`agent`, `audio`, `capture`,
  `cmd`, `hw`, `install`, `pkg`, `refresh`, `restart`, `theme`, `toggle`,
  `update`, ...). Groups whose commands are all `hidden=true` get no entry
  (`apply-`, `provision-` are deliberately absent) — `AGENTS.md` "Command
  Naming".

## Runtime environment

- `$OMARCHY_PATH` is a session invariant set by uwsm; bash and QML rely on it
  (`Quickshell.env("OMARCHY_PATH")`) and never derive fallbacks from `HOME` or
  `Quickshell.shellDir` (`AGENTS.md`, `shell/shell.qml:26`).
- Privilege: the `sudo`/`pkexec` line follows whether the caller has a
  terminal (`AGENTS.md` "Privileged Commands",
  `default/agents/skills/omarchy/SKILL.md`); commands that need root carry
  `# omarchy:requires-sudo=true` (`bin/omarchy-pkg-add:5`).

## QML (shell/)

- Entry `shell/shell.qml` is a `ShellRoot`; plugin entry points are `Item`s
  receiving injected `omarchyPath`, `shell`, `manifest`, `pluginRegistry` /
  `barWidgetRegistry` (`agents/skills/shell-dev.md:23`).
- **Import order**: Qt modules, then Quickshell modules, then `qs.Commons` /
  `qs.Ui`, then relative JS `import "MenuModel.js" as MenuModel`
  (`shell/shell.qml:1-9`, `shell/plugins/menu/Menu.qml:1-7`).
- **Component shape**: root `id: root` (or `id: shell`), then public
  `property` declarations grouped under short comment banners (state flags,
  colors, sizing), `signal`s, functions, `readonly property` internals
  prefixed `_` (`_borderSpec`, `_showFocusRing` in `shell/Ui/Button.qml:78-110`),
  then layout properties and children. Long files document state precedence in
  a header comment (`Button.qml:5-19`).
- **Theming**: colors/sizing come from `Color.*` and `Style.*` tokens in
  `qs.Commons`, not literals (`Button.qml:35-46`).
- **Model.js files**: plain ES5-style functions and `var`, ending in a guarded
  `if (typeof module !== "undefined") { module.exports = {...} }` so QML
  imports them directly while Node `require`s them in tests
  (`shell/plugins/menu/MenuModel.js:493`, `shell/plugins/bar/BarModel.js:211`).
- **Plugin layout**: `shell/plugins/<name>/` with `manifest.json`
  (`schemaVersion`, `id` like `omarchy.menu`, `name`, `version`, `kinds`,
  `entryPoints`) plus `Menu.qml`/`Bar.qml`/`BarWidget.qml` entry points
  (`shell/plugins/menu/manifest.json`). First-party bar widgets may use
  adjacent `*.manifest.json` (`shell/plugins/bar/widgets/Workspaces.manifest.json`).
  Panel/menu plugins expose `open(payloadJson)` and `close()`
  (`shell-dev.md:24`). Widget files contain raw Nerd Font glyphs — do not
  rewrite them wholesale (`shell-dev.md:41-47`).

## Lua (config/, default/hypr/)

- `config/hypr/hyprland.lua` is the shipped user entry: `dofile` the
  `default/hypr/bootstrap.lua` via `os.getenv("OMARCHY_PATH")`, then
  `require("default.hypr.omarchy")` plus user override files
  (`config/hypr/hyprland.lua`). Defaults live in `default/hypr/*.lua` as
  `require("default.hypr.<mod>")` modules with optional loads via
  `require_optional.module(...)` (`default/hypr/omarchy.lua`). Filenames are
  lowercase (`looknfeel.lua`, `bindings/`).

## File naming and other trees

- `migrations/<unix-timestamp>.sh`: mode 0644, no shebang, first line an
  `echo` describing the change, must be idempotent, created via
  `omarchy-dev-add-migration` (`agents/skills/migrations.md:107-129`).
- `install/` leaf scripts are sourced by `run_logged` — no shebang, avoid
  `exit`, use `$OMARCHY_INSTALL`/`$OMARCHY_PATH`; root setup under
  `install/hardware/`, per-user under `install/user/`
  (`agents/skills/install-scripts.md`).
- Tests: `test/shell.d/<area>-test.sh`; shared fixtures in
  `test/shell.d/fixtures/`.
- Git: atomic commits, succinct messages (`AGENTS.md` "Git").
- Markdown: full lines, no hard wrapping (`AGENTS.md` "Style").
