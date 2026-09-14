# Roadmap: Omarchy Fork — Per-Monitor Display Scaling

## Overview

Fix per-monitor display scaling on the Omarchy fork in two atomic phases. First, repair `bin/omarchy-hyprland-monitor-scaling` so a scale change persists to the target monitor's own `hl.monitor()` line in `~/.config/hypr/monitors.lua` and preserves its configured position in the live apply — ending the silent revert after reload/reboot. Then update `shell/plugins/panels/monitor/` so each screen's bar Display panel targets the monitor it sits on and shows each monitor's current scale. The split keeps each change single-concern and reviewable per Omarchy conventions, and maps to two potential upstream PRs.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Per-monitor scale persistence in the scaling CLI** - `omarchy-hyprland-monitor-scaling` rewrites the target monitor's own `hl.monitor()` line and preserves configured position on live apply
- [ ] **Phase 2: Per-monitor Display panel** - Each screen's bar panel targets its own monitor and the DISPLAYS section shows per-monitor scale

## Phase Details

### Phase 1: Per-monitor scale persistence in the scaling CLI

**Goal**: `bin/omarchy-hyprland-monitor-scaling` persists a scale change to the target monitor's own `hl.monitor()` line in `~/.config/hypr/monitors.lua` and keeps the monitor's configured position when applying live via `hyprctl eval`
**Depends on**: Nothing (first phase)
**Requirements**: SCALE-01, SCALE-02, SCALE-03, SCALE-04
**Success Criteria** (what must be TRUE):

  1. Changing scale via `omarchy hyprland monitor scaling` rewrites the target monitor's own `hl.monitor()` line in `~/.config/hypr/monitors.lua`, and the new scale is still in effect after `hyprctl reload` and after reboot
  2. The live apply preserves the monitor's configured position — the Samsung at `-1200x0` stays put instead of being forced to `position = "auto"`
  3. Persistence still works on stock configs that use the `omarchy_monitor_scale` variable or a literal catch-all line (no regression)
  4. Persistence handles realistic `monitors.lua` shapes: multi-line `hl.monitor({...})` entries, `desc:` selectors, and monitors without an explicit scale

**Plans**: 1/1 plans executed

Plans:

- [x] 01-01-PLAN.md
- [x] 01-01: Rewrite scale persistence to target the monitor's own `hl.monitor()` line and preserve configured position in the live `hyprctl eval` apply

### Phase 2: Per-monitor Display panel

**Goal**: `shell/plugins/panels/monitor/` targets the monitor each bar instance sits on and shows each monitor's current scale in the DISPLAYS section
**Depends on**: Phase 1
**Requirements**: SCALE-05, SCALE-06, SCALE-07
**Success Criteria** (what must be TRUE):

  1. SCALE pills on the Samsung's bar (left, `HDMI-A-1`) change the Samsung's scale; pills on the laptop bar (right, `eDP-1`) change `eDP-1` — each bar targets its own screen, not the globally focused monitor
  2. The DISPLAYS section shows each monitor's name with its current scale (e.g. `HDMI-A-1 · 1.6x`)
  3. A scale change made from the panel persists to the correct monitor's `hl.monitor()` line and survives reload/reboot (via the Phase 1 CLI)
  4. Single-monitor setups still work — the scale row functions and the panel behaves as before

**Plans**: 1/1 plans executed

Plans:

- [x] 02-01-PLAN.md
- [x] 02-01: Per-bar monitor targeting for SCALE pills plus per-monitor scale display in the DISPLAYS section

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Per-monitor scale persistence in the scaling CLI | 1/1 | In Progress|  |
| 2. Per-monitor Display panel | 1/1 | In Progress | - |

### Phase 3: Scale-aware monitor position adjustment

**Goal**: `omarchy-hyprland-monitor-scaling` recomputes the target monitor's position on scale change so edge-adjacent monitors stay adjacent — no new overlaps, no dead gaps that trap the cursor — persists the corrected position to `monitors.lua`, and makes `GDK_SCALE` track the maximum monitor scale instead of the last-scaled monitor's
**Depends on**: Phase 2
**Requirements**: SCALE-08, SCALE-09, SCALE-10
**Success Criteria** (what must be TRUE):

  1. Rescaling an edge-adjacent monitor keeps it touching its neighbor — e.g. Samsung `HDMI-A-1` at `-1200x0` scale 1.6 → scale 1.5 lands at `-1280x0`, no overlap warning, cursor can still cross
  2. Rescaling a floating monitor either preserves its position exactly or minimally clamps it only when the growth would create a new overlap — deliberate gaps are never silently normalized
  3. The recomputed position is written to the target monitor's `hl.monitor()` rule and survives `hyprctl reload`
  4. `omarchy_gdk_scale` reflects `round(max(all monitor scales))` after any scale change, so scaling a secondary monitor cannot degrade XWayland sharpness on a denser primary

**Plans**: 1 plan

Plans:

- [x] 03-01-PLAN.md — scale-aware position recompute + persistence + max-scale GDK (4 tasks, 1 wave)
