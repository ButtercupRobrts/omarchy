# Omarchy Fork — Per-Monitor Display Scaling

## What This Is

A personal fork of Omarchy (`omacom/omarchy` → `ButtercupRobrts/omarchy`) used for developing fixes against the live system and potentially upstreaming them. Current focus: make per-monitor display scaling actually work — each screen's bar Display panel can see and set its own monitor's scale, and scale changes persist to the correct `hl.monitor()` line in `~/.config/hypr/monitors.lua` so they survive reboot.

## Core Value

A monitor scale change made from the bar or CLI must apply to the intended monitor and still be in effect after reboot — the current tool silently reverts it.

## Requirements

### Validated

- ✓ Hyprland accepts arbitrary "clean" per-output scales — existing
- ✓ `omarchy-hyprland-monitor-scaling` applies scale live via `hyprctl eval` — existing
- ✓ Display panel (`omarchy.monitor`) already has a SCALE section with preset pills — existing
- ✓ Shell runs one bar instance per screen (`Variants { model: Quickshell.screens }`) — existing
- ✓ `SUPER + /` / `SUPER + ALT + /` scaling keybindings exist — existing

### Active

- [ ] REQ-01 — Scale changes persist to the target monitor's own `hl.monitor()` line in `monitors.lua` (per-monitor persistence that survives reboot)
- [ ] REQ-02 — Live scale apply preserves the monitor's configured position instead of forcing `position = "auto"`
- [ ] REQ-03 — Each screen's bar Display panel can scale the monitor it sits on (own-screen targeting), not only the globally focused monitor
- [ ] REQ-04 — DISPLAYS section shows each monitor's current scale (e.g. `HDMI-A-1 · 1.6x`)
- [ ] REQ-05 — Single-monitor setups keep working with no regression

### Out of Scope

- GDK_SCALE / activation-environment sync — upstream issue #10555 / PR #10570; separate layer, separate change
- SDDM greeter monitor scale — issue #7312; greeter config, unrelated to the shell panel
- Screensaver scale/art issues — #9027, #7307; unrelated visuals
- Brightness controls — already functional in the panel
- Building on open PR #11414's branch — independent implementation chosen instead

## Context

- Live setup under development: `eDP-1` laptop at scale 1.5, `HDMI-A-1` Samsung at scale 1.6 positioned `-1200x0` (left). `monitors.lua` has explicit per-monitor `hl.monitor()` lines after the generic catch-all.
- Bug chain: `omarchy-hyprland-monitor-scaling` applies live via `hyprctl eval` with hardcoded `position = "auto"` (clobbers configured layout until reload), then persists by rewriting the shared `omarchy_monitor_scale` variable — which explicit per-monitor lines override on every reload → silent revert (upstream issue #9950, also #7242, #8103, #6673, #10922).
- ~9 competing open upstream PRs attack the persistence half (#11414 most recent); none merged. Independent implementation keeps our change reviewable and standalone.
- Panel plumbing verified: `KeyboardPanel` exposes `screen` (from `anchorWindow.screen`), so a per-bar-monitor target is reachable in QML. `omarchy-monitor-state`'s displays JSON lacks per-display scale — panel must read `hyprctl monitors -j` itself or the state contract must be extended.
- Repo conventions: atomic single-concern commits, `test/shell.d/*-test.sh` suites (existing `monitor-scaling-test.sh` only covers persistence branch 1), visual verification required for UI changes, Nerd Font glyph care when editing QML.

## Constraints

- **Compatibility**: must handle all existing `monitors.lua` shapes — `omarchy_monitor_scale` variable, literal catch-all, explicit per-monitor lines, multi-line entries, `desc:` selectors
- **Style**: Omarchy AGENTS.md rules — atomic commits, `[[ ]]`/`(( ))` bash, `# omarchy:*` metadata headers, `#!/bin/bash` shebangs
- **Testing**: iterate via `~/.config/omarchy/plugins/` clone (hot-reload); final verification via `omarchy dev link`
- **Safety**: never edit `/usr/share/omarchy` on the live system — changes ship through the repo
- **Regression**: `monitor-clamshell-scale-test.sh` and related suites must stay green

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| GSD project lives in the fork repo | The code under change lives here; `.planning/` alongside keeps plan and code together | — Pending |
| Two-phase split (CLI fix, then panel UI) | Omarchy requires atomic single-concern changes; maps to two clean potential upstream PRs | — Pending |
| Independent implementation, not building on PR #11414 | ~9 competing unmerged PRs for the same bug; a standalone change is more reviewable | — Pending |
| Test via plugin clone AND dev link | Hot-reload iteration plus real end-to-end verification | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-14 after initialization*
