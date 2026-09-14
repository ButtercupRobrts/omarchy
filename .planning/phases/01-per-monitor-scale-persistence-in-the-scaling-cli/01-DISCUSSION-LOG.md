# Phase 1: Per-monitor scale persistence in the scaling CLI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-14
**Phase:** 1-per-monitor-scale-persistence-in-the-scaling-cli
**Areas discussed:** Rewrite strategy, Unlisted monitors, CLI targeting arg, Position + safety

---

## Rewrite strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid | In-place rewrite of the monitor's own `hl.monitor()` line when it exists; append a per-monitor line when it doesn't | ✓ |
| In-place only | Only rewrite existing matching lines; unlisted monitors fall back to catch-all rewrite | |
| Append-only | Always append a managed `hl.monitor()` line; never touch existing entries | |

**User's choice:** Hybrid (recommended)
**Notes:** Presented with a senior-engineer rundown: in-place alone can't cover unlisted monitors; append-only abandons user formatting and leaves stale lines that later hand-edits would silently not affect.

## Unlisted monitors

| Option | Description | Selected |
|--------|-------------|----------|
| Append explicit line | Write a new per-monitor `hl.monitor()` with live mode/position + new scale. True per-monitor persistence | ✓ |
| Rewrite shared catch-all | Keep stock behavior — changes every monitor sharing the catch-all on reload (upstream bug #6673) | |

**User's choice:** Append explicit line (recommended)
**Notes:** Catch-all rewrite is the bug being fixed, not a fallback — appending always works.

## CLI targeting arg

| Option | Description | Selected |
|--------|-------------|----------|
| Optional [monitor] arg | `omarchy hyprland monitor scaling 1.5 HDMI-A-1` — Phase 2 reuses all persistence logic | ✓ |
| Focused-only | Keep CLI as-is; panel implements its own apply+persist — duplicates logic in QML/JS | |

**User's choice:** Optional [monitor] arg (recommended)
**Notes:** Backward compatible; avoids duplicating the sed/parser logic that CONCERNS.md flags as drift-prone (`omarchy-hyprland-monitor-clamshell` already parses the same file in parallel).

## Position + safety

| Option | Description | Selected |
|--------|-------------|----------|
| Live x/y + backup | Replay live position from hyprctl; `cp monitors.lua .bak.<ts>` before rewriting | ✓ |
| Live x/y, no backup | Preserve position but keep the current no-backup sed behavior | |
| Parse position from file | Read `position =` from monitors.lua instead of live state | |

**User's choice:** Live x/y + backup (recommended)
**Notes:** File position can say `auto` while the live position is `-1200x0` — live state is always correct. Backup matches Omarchy's refresh pattern and the user's existing `.bak` habit.

## the agent's Discretion

- GDK_SCALE update mechanics (keep nearest-integer update; env sync is v2 SCALE-20)
- Exact test-case breakdown within `test/shell.d/monitor-scaling-test.sh`
- Audit log field shape (unchanged)

## Deferred Ideas

- GDK_SCALE activation-environment sync — v2 SCALE-20
- SDDM greeter scale — v2 SCALE-21
- Keybinding-driven per-monitor targeting — v2 SCALE-22
