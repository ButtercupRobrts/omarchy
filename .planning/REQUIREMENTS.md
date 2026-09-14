# Requirements: Omarchy Fork — Per-Monitor Display Scaling

**Defined:** 2026-09-14
**Core Value:** A monitor scale change made from the bar or CLI must apply to the intended monitor and still be in effect after reboot.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Scaling Persistence

- [ ] **SCALE-01**: A scale change for a monitor persists by updating that monitor's own `hl.monitor()` line in `~/.config/hypr/monitors.lua` — it survives `hyprctl reload` and reboot
- [ ] **SCALE-02**: A live scale change preserves the monitor's configured position (e.g. `-1200x0`) instead of forcing `position = "auto"`
- [ ] **SCALE-03**: Persistence still works when `monitors.lua` uses the stock `omarchy_monitor_scale` variable or literal catch-all (no regression for default configs)
- [ ] **SCALE-04**: Persistence handles realistic `monitors.lua` shapes — multi-line `hl.monitor({...})` entries, `desc:` selectors, monitors without explicit scale

### Bar Panel

- [ ] **SCALE-05**: The Display panel on each screen's bar shows and targets that screen's own monitor for SCALE pills (per-bar monitor targeting)
- [ ] **SCALE-06**: The DISPLAYS section shows each monitor's current scale alongside its name
- [ ] **SCALE-07**: The panel behaves correctly with a single monitor (scale row works, no DISPLAYS section needed)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Scaling Ecosystem

- **SCALE-20**: Sync `GDK_SCALE` into the app-launch/activation environment on scale change (upstream issue #10555)
- **SCALE-21**: Apply session monitor scale to the SDDM greeter (upstream issue #7312)
- **SCALE-22**: Keybinding-driven per-monitor targeting (scale a chosen monitor without focusing it first)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Brightness controls in the panel | Already functional — not part of this fix |
| Screensaver scale/art fixes | Unrelated upstream issues #9027, #7307 |
| Building on PR #11414 branch | Independent implementation for a clean, standalone change |
| Rewriting `omarchy-monitor-state` positional contract | Panel reads `hyprctl monitors -j` itself for per-display scale; avoids destabilizing the 8-line contract other consumers may parse |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SCALE-01 | Phase 1 | Pending |
| SCALE-02 | Phase 1 | Pending |
| SCALE-03 | Phase 1 | Pending |
| SCALE-04 | Phase 1 | Pending |
| SCALE-05 | Phase 2 | Pending |
| SCALE-06 | Phase 2 | Pending |
| SCALE-07 | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 7 total
- Mapped to phases: 7
- Unmapped: 0 ✓

---
*Requirements defined: 2026-09-14*
*Last updated: 2026-09-14 after initial definition*
