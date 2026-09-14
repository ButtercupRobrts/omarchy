# Phase 1: Per-monitor scale persistence in the scaling CLI - Context

**Gathered:** 2026-09-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix `bin/omarchy-hyprland-monitor-scaling` so a scale change persists to the target monitor's own `hl.monitor()` line in `~/.config/hypr/monitors.lua` (survives `hyprctl reload` and reboot), preserves the monitor's configured position in the live `hyprctl eval` apply, and gains an optional `[monitor]` positional arg for non-focused targeting. Covers SCALE-01..SCALE-04. The Display panel UI work is Phase 2 — this phase is CLI + persistence only.

</domain>

<decisions>
## Implementation Decisions

### Rewrite strategy
- **D-01:** Hybrid persistence — when the target monitor has an explicit `hl.monitor()` entry in `monitors.lua`, rewrite its `scale =` field in place (insert the field if the entry lacks one); when it has none, append a new per-monitor `hl.monitor()` line carrying live mode/position plus the new scale. In-place rewrite must handle multi-line `hl.monitor({...})` entries, `desc:` selectors, and entries without a `scale` field.

### Unlisted monitors
- **D-02:** Never persist via the shared `omarchy_monitor_scale` variable or the literal catch-all `hl.monitor({ output = "" ... })` line when a specific monitor was targeted — appending an explicit per-monitor line is always the correct action. (Rewriting the catch-all rescales every monitor sharing it on reload — upstream issue #6673.)

### CLI surface
- **D-03:** Add an optional positional `[monitor]` argument — `omarchy hyprland monitor scaling <scale|up|down> [monitor]` — defaulting to the focused monitor when omitted. Backward compatible; Phase 2's per-bar panel passes its own screen name through it. — **Reversibility:** costly — once the panel and any user scripts call it, removing the arg breaks callers; adding it is trivially safe.

### Live apply and file safety
- **D-04:** The live `hyprctl eval` apply must replay the target monitor's live `x,y` position (read from `hyprctl monitors -j`) instead of hardcoding `position = "auto"`, so configured layouts like `-1200x0` are not clobbered.
- **D-05:** Back up `monitors.lua` to `monitors.lua.bak.<timestamp>` before any rewrite of the file.

### the agent's Discretion
- GDK_SCALE handling: keep updating it as today (nearest integer); full activation-environment sync is out of scope (v2 SCALE-20).
- Test coverage shape: extend `test/shell.d/monitor-scaling-test.sh` following `base-test.sh` conventions — planner decides exact cases, must include per-monitor line rewrite, append-when-unlisted, position preservation, and the stock catch-all path.
- Audit log (`~/.local/state/omarchy/monitor-scaling.log`) format unchanged.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Code under change
- `bin/omarchy-hyprland-monitor-scaling` — the script being fixed; note `set_scale()` (live eval + persistence branches), `clean_scale()`, and `scale_from_current()`
- `bin/omarchy-hyprland-monitor-clamshell` — second sed/regex parser of `monitors.lua`; must stay compatible with lines this phase writes
- `bin/omarchy-monitor-state` — positional state contract consumed by the Display panel

### Conventions and tests
- `AGENTS.md` — style rules (atomic commits, `[[ ]]`/`(( ))`, `#!/bin/bash`, `# omarchy:*` metadata headers)
- `test/shell.d/monitor-scaling-test.sh` — existing suite to extend (currently covers only the `omarchy_monitor_scale` variable branch)
- `test/shell.d/base-test.sh` — shared test helpers contract
- `docs/testing.md` — how to run focused suites
- `.planning/codebase/CONCERNS.md` — catalog of the sed-fragility and position-clobber issues this phase fixes

### Upstream context (reference only — do not build on these branches)
- Upstream issue #9950 — exact bug report (panel presets silently no-op with per-output lines)
- Upstream issue #6673 — per-monitor runtime, global persistence coupling
- Upstream issue #10922 — `position = "auto"` desyncs live multi-monitor layout
- Upstream PR #11414 — competing fix; independent implementation decided

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `clean_scale()` and `scale_from_current()` in `bin/omarchy-hyprland-monitor-scaling`: already handle Hyprland's clean-scale snapping and preset stepping — unchanged by this phase
- `audit_scale_change()`: logging hook — extend its fields only if needed, do not break the log format
- `hl.monitor()` catch-all + explicit-line layering in `monitors.lua`: later rules win — this is what makes "append explicit line" work

### Established Patterns
- `omarchy-refresh-config` backs up before overwriting user config — mirror that with the timestamped `.bak` (D-05)
- `test/shell.d/*-test.sh` suites source `base-test.sh` and run under a stub `$HOME` — tests exercise the script against fixture `monitors.lua` files
- `# omarchy:summary/args/examples` metadata headers drive `omarchy commands` output — update `omarchy:args` when adding `[monitor]`

### Integration Points
- `shell/plugins/panels/monitor/Panel.qml` `setScale()` calls `omarchy-hyprland-monitor-scaling <scale>` — Phase 2 will pass its own screen name through the new arg; this phase only needs the CLI to accept it
- `omarchy-hyprland-monitor-clamshell` parses the same file — appended per-monitor lines must use the same single-line `hl.monitor({ ... })` shape it already understands

</code_context>

<specifics>
## Specific Ideas

- Target machine's real config is the primary fixture: `eDP-1` at scale 1.5 and `HDMI-A-1` at 1.6 with `position = "-1200x0"`, explicit per-monitor lines after the catch-all — the exact shape that triggers the silent-revert bug
- Upstream issue #9950's thread contains a reporter's per-monitor implementation notes — useful reference for edge cases (N monitors, `desc:` selectors) but we implement independently

</specifics>

<deferred>
## Deferred Ideas

- GDK_SCALE sync into the activation/app-launch environment — v2 SCALE-20 (upstream #10555)
- SDDM greeter scale — v2 SCALE-21 (upstream #7312)
- Keybinding-driven per-monitor targeting (scale a chosen monitor without focusing it) — v2 SCALE-22

</deferred>

---

*Phase: 1-Per-monitor scale persistence in the scaling CLI*
*Context gathered: 2026-09-14*
