# Concerns

Areas a planner must handle carefully. Every claim is grounded in a file that
was read; line numbers are included where stable.

## `bin/omarchy-hyprland-monitor-scaling` rewrites `~/.config/hypr/monitors.lua`

`set_scale` (lines 74–113) live-applies via `hyprctl eval` (line 97) and then
persists by `sed -i`-ing the user's `monitors.lua` through **two disjoint
branches**, chosen by regex shape of the file:

- **Branch 1** (line 102): fires only when a `local omarchy_monitor_scale = `
  line exists; rewrites that local and `local omarchy_gdk_scale`. This matches
  the shipped default (`config/hypr/monitors.lua` lines 7, 21). Gap: if the
  user added per-monitor `hl.monitor` rules with **literal** scales (the
  commented examples at `config/hypr/monitors.lua` lines 11–14 invite exactly
  this), the variable still gets rewritten but the literal rule wins for that
  output — the persisted scale silently does not apply to it.
- **Branch 2** (line 107): fires only on the exact literal catch-all
  `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = ("auto"|[0-9.]+) })`.
  Reordered keys, extra whitespace, a `transform`, or a variable reference
  (`scale = omarchy_monitor_scale`) all fail the match. Its GDK rewrite
  (line 110) likewise only matches `hl.env("GDK_SCALE", "<literal>")`, not the
  shipped `tostring(omarchy_gdk_scale)` form.
- **Neither branch** matches a config built only from per-output rules: the
  change applies live but is lost at reboot with no warning to the user.
- `sed -i` runs with **no backup** — unlike `omarchy-refresh-config`, which
  saves `*.bak.<timestamp>` (`bin/omarchy-refresh-config` lines 31–39).

### `position = "auto"` clobbering

The live `hyprctl eval` (line 97) hardcodes `position = "auto"` and pins mode
to the *current* `widthxheight@refreshRate`. A monitor with a configured
explicit position (`"0x0"`, `"auto-right"` — both appear in
`test/shell.d/monitor-clamshell-scale-test.sh` fixtures at lines 87–88, 196)
gets repositioned as a side effect of a scale change. The clamshell helper
`bin/omarchy-hyprland-monitor-clamshell` reads the configured position back
(`read_monitor_position`, lines 156–165), but the scaling command does not.

### A second, parallel parser

`bin/omarchy-hyprland-monitor-clamshell` (lines 38–108) re-parses
`monitors.lua` with its own sed/regex machinery (`monitor_rules`,
`configured_monitor_value`, `lua_local_value`), including comment stripping
and variable resolution. Any change to the file's shape or to the scaling
script's write format must be reconciled with this parser — the two disagree
by design about which rule owns a scale (comments at lines 100–105, 185–191).

## Shell / QML gotchas (`agents/skills/shell-dev.md`)

- **One Quickshell process**: the whole desktop is a single `quickshell -n -p`
  instance (shell-dev.md lines 5–8). Never spawn standalone instances; run
  `omarchy-restart-shell` after QML edits (line 10).
- **Nerd Font glyph corruption**: widget files under
  `shell/plugins/bar/widgets/` embed raw multibyte glyphs that file-editing
  tools can strip (shell-dev.md lines 41–47, e.g. `SystemUpdate.qml` line 59
  `"\uf021"`). Targeted edits only, or Python `chr(0xXXXXX)` insertion — never
  wholesale rewrites.
- **Facades are not sandboxes**: third-party plugins get capability-scoped
  facades, but a widget can walk its parent hierarchy to host objects;
  authentication services must stay out of `ShellRoot._services` and the host
  QObject tree (shell-dev.md line 23; `docs/omarchy-shell.md` plugin section).
- **IPC quirks** (`bin/omarchy-shell`): `qs ipc` reports "Target not found."
  / "Function not found." / arg-count errors **on stdout with exit 0**
  (lines 55–77); a starting shell answers "Not ready to accept queries yet"
  and must be treated as unreachable (lines 72–76). Calls are bounded by
  `OMARCHY_SHELL_IPC_TIMEOUT` (default 2s, line 58). `WAYLAND_DISPLAY` is
  recovered from the compositor socket for out-of-session callers
  (lines 46–49).
- **Process re-entrancy**: plugins guard spawns with
  `if (!proc.running)` (`shell/plugins/bar/widgets/SystemUpdate.qml` line 14;
  `shell/plugins/lock/Service.qml` lines 101, 113, 117, 180, 187, 473).
  Forgetting the guard double-spawns; `onExited` handlers that set state from
  `exitCode` (SystemUpdate.qml lines 42–44) leave stale state if the process
  is killed by a shell restart. The lock service coordinates six+ async
  Processes plus IPC — highest-risk file for races.
- **Plugin discovery race**: `bin/omarchy-plugin-clone` calls
  `rescanPlugins` then polls `omarchy-plugin-list` 40×50 ms for the new id
  (lines 149–158) — a fixed 2 s budget that can fail on a busy shell.

## Migrations discipline

- `migrations/*.sh` are named by **unix timestamp** (114 files,
  `1778623107.sh` … `1788941927.sh`), glob-ordered so name sort == run order.
  Create via `omarchy-dev-add-migration --no-edit`
  (`agents/skills/migrations.md` lines 107–120).
- Files must be `0644`, **no shebang**, start with an `echo`, run under
  `bash -euo pipefail` (`bin/omarchy-migrate` line 93; migrations.md
  lines 122–126).
- Per-user run-once markers live at
  `~/.local/state/omarchy/migrations/<file>` (`bin/omarchy-migrate` lines
  32, 91–96). Every user runs every migration; machine-wide repairs must
  no-op for later users (migrations.md lines 22–32).
- **Strictly ordered and synchronous**: a failing migration must exit
  non-zero and stops the queue — never mark later migrations done against
  state an earlier one didn't establish (migrations.md line 129;
  `omarchy-migrate` aborts on the failing script via `-e`).
- `omarchy-migrate` waits up to 900 s on `/var/lib/pacman/db.lck` then
  **exits 0 silently** (lines 68–81) — the update proceeds and pending
  migrations defer to the login notifier. Never restart the shell from a
  migration (migrations.md lines 133–135). Pre-4.0 layout transitions belong
  in `bin/omarchy-upgrade-to-quattro`, not migrations (lines 168–172).

## Update-safety: `/usr/share/omarchy` is packaged

- The runtime tree is owned by the `omarchy` package; updates run
  `pacman -Syu --overwrite '/usr/share/omarchy/*'`
  (`bin/omarchy-update-system-pkgs` lines 13, 27) — user edits under
  `/usr/share/omarchy` are **overwritten without a pacnew warning**.
- `omarchy-settings` additionally `cp -f`s `etc-overrides/` into `/etc` on
  every upgrade, clobbering admin edits (`docs/file-layout.md` lines
  144–155). `.pacnew`/`.pacsave` handling is a known gap
  (`docs/update-process.md` lines 328–330).
- Correct customization path for shell plugins: clones/adds under
  `~/.config/omarchy/plugins/<id>/` (`bin/omarchy-plugin-clone` line 9;
  `docs/omarchy-shell.md`). For shipped user configs, the supported flow is
  edit `~/.config/**` directly or resync via `omarchy-refresh-config`
  (backup-on-copy) / `omarchy-reinstall-configs` (destructive).
- During package transactions, ALPM hooks pause Hyprland autoreload via
  `omarchy-hyprland-reload-guard` (`docs/update-process.md` lines 101–107;
  `bin/omarchy-hyprland-reload-guard` writes per-instance state under
  `/run/omarchy/hyprland-reload-guard/`) — config writes made while paused
  take effect only after the resume reload.
- `omarchy-refresh-config` interpolates its argument into both paths and only
  checks `[[ -e ]]` — a `..`-bearing path escapes `~/.config`
  (`bin/omarchy-refresh-config` lines 20–27; flagged in `AGENTS.md`).

## Error-handling and test-coverage holes

- `monitor-scaling-test.sh` exercises **only branch 1** persistence (its
  `write_monitor_config` at lines 32–37 writes just the locals). The
  branch-2 literal catch-all rewrite (lines 107–112), the silent
  no-persist path, and the `position = "auto"` clobber are all untested.
- `audit_scale_change` appends to
  `~/.local/state/omarchy/monitor-scaling.log` with **no rotation** and
  best-effort failure handling (`|| return 0`, line 36).
- `bin/omarchy-monitor-state` emits an **8-line positional contract** that
  the QML panel reads by index; a helper dying mid-script shifts every field
  (documented in `test/shell.d/monitor-state-test.sh` lines 32–34). Any
  output change must keep line count and order.
- Graphical acceptance tests run only in a disposable VM; `./test/all`
  deliberately skips them (`AGENTS.md` Tests section) — visual/session
  regressions in scaling and monitor flows aren't caught by the default
  suite.
- `set -euo pipefail` is inconsistent across `bin/`:
  `omarchy-hyprland-monitor-scaling` and `omarchy-hyprland-monitor-clamshell`
  run without it (relying on explicit guards like the monitor-name regex at
  `omarchy-hyprland-monitor-scaling` line 86 and
  `omarchy-hyprland-monitor-clamshell` line 17), while `omarchy-migrate` and
  `omarchy-plugin-clone` set it. Don't assume a script aborts on error.
