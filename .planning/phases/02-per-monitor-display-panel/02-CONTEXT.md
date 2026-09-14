# Phase 2: Per-monitor Display panel - Context

**Gathered:** 2026-09-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the `omarchy.monitor` Display panel per-monitor-aware: the panel instance on each screen's bar targets that screen's own monitor for SCALE pills (not the globally focused monitor), the DISPLAYS section shows each monitor's current scale, and single-monitor setups still work. Scale application goes through the Phase 1 CLI (`omarchy-hyprland-monitor-scaling <scale> [monitor]`) so persistence, position preservation, and backups are inherited — no parallel persistence logic in QML/JS.

Requirements: SCALE-05 (per-bar targeting), SCALE-06 (per-display scale in DISPLAYS rows), SCALE-07 (single-monitor behavior).

</domain>

<decisions>
## Implementation Decisions

### Scale visibility in DISPLAYS rows
- **D-01:** Each monitor row shows its scale as an inline suffix matching the existing row style — `HDMI-A-1 · 1.6x` — not a right-aligned column or pill/badge.

### DISPLAYS row interaction
- **D-02:** Clicking a display row keeps the stock enable/disable toggle. The scale is display-only text; no new click action is added to the row.

### SCALE section header
- **D-03:** The SCALE header shows the target monitor's name AND its current scale — `SCALE — HDMI-A-1 · 1.6x` — replacing the stock "name only when 2+ displays" behavior. On a single monitor the name is still meaningful (it identifies which output the pills act on) but the exact single-monitor header form is the agent's discretion.

### Non-preset scale values
- **D-04:** When the monitor's actual scale is not one of the presets (1, 1.25, 1.6, 2, 3, 4 — e.g. 1.5, 1.875), it must still be visible: shown in the header text (per D-03) AND surfaced as a dynamic "current" pill inserted into the preset row so the value is discoverable and the active state is unambiguous.

### Targeting mechanism
- **D-05:** The panel targets the monitor whose bar hosts the panel instance — resolved from the widget's own window screen (the same source `Bar.qml`'s `slotScreenName` uses), not `Hyprland.focusedMonitor`. A keyboard-summoned panel opens on the focused screen's bar and therefore targets the focused screen — self-consistent.

### Scale plumbing
- **D-06:** Per-display scale reaches the panel by extending `omarchy-monitor-state`'s line-7 displays JSON with a `scale` field — a one-word additive jq change that leaves the 8-line positional contract untouched and keeps a single Process/update path. **This supersedes the init decision** (recorded in REQUIREMENTS.md Out-of-Scope and STATE.md) that had the panel reading `hyprctl monitors -j` itself; the init rationale (don't destabilize the positional contract) is satisfied because the line count and ordering do not change.

### the agent's Discretion
- Exact single-monitor header form when only one display exists.
- Whether the current-scale pill highlight uses the existing `matchingScaleIndex` machinery.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 1 artifacts (this project)
- `.planning/phases/01-per-monitor-scale-persistence-in-the-scaling-cli/01-CONTEXT.md` — locked decisions D-01..D-05 that produced the CLI contract this phase consumes
- `.planning/phases/01-per-monitor-scale-persistence-in-the-scaling-cli/01-VERIFICATION.md` — verified Phase 1 behavior (positional `[monitor]` arg, name validation, audit fields)

### Project rules
- `AGENTS.md` — QML/shell task guides; `agents/skills/shell-dev.md` (Quickshell work), `agents/skills/visual-verification.md` (UI changes require running-UI verification)

### Upstream context (referenced during earlier research — informational)
- omacom/omarchy issue #9950 — per-monitor scaling and the bar panel are mutually exclusive (the bug this milestone fixes)
- omacom/omarchy PR #11414 — upstream attempt at widget coupling fix (do NOT build on it; reference only)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `shell/plugins/bar/Bar.qml:706` `slotScreenName(slot)` — extracts `window.screen.name` per widget instance; the pattern for a widget discovering its own screen (also `Ui/KeyboardPanel.qml:80` `screen: anchorWindow.screen`)
- `bin/omarchy-hyprland-monitor-scaling` (Phase 1) — accepts `[SCALE] [monitor]`; the panel passes its own screen name as arg 2, inheriting persistence/position/backups
- `bin/omarchy-monitor-state` — panel state source; displays JSON array already carries per-monitor objects (`name, enabled, focused, width, height`) — adding `scale` is a non-breaking extension; the 8-line positional contract and bare-scaling-call line 6 must not shift
- `shell/plugins/panels/monitor/Model.js` — `normalizeScale`, `cleanScale`, `availableScales`, `matchingScaleIndex` already exist for scale value math and preset filtering

### Established Patterns
- `Panel.qml:308` `actionProc.command = ["bash","-c","omarchy-hyprland-monitor-scaling " + scale]` — the single call site to extend with the monitor arg
- `Panel.qml:388` `stateProc` runs `omarchy-monitor-state`; `updateDisplays(lines[7])` parses the displays JSON
- Bar instances are per-screen (`Variants { model: Quickshell.screens }`); `BarModel.pickPanelSlot` already routes keyboard summons to the focused screen's widget instance
- `displays.length > 1` already gates the DISPLAYS section and monitor-name label (SCALE-07 collapses automatically)

### Integration Points
- `shell/plugins/panels/monitor/Panel.qml` — setScale call site, SCALE header text, DISPLAYS row rendering
- `shell/plugins/panels/monitor/Model.js` — parse displays scale, dynamic current pill
- `bin/omarchy-monitor-state` — per-display `scale` field in the JSON (if that plumbing wins)

</code_context>

<specifics>
## Specific Ideas

- Scale row format should match the existing `name · focused` aesthetic: `HDMI-A-1 · 1.6x`
- Header example: `SCALE — HDMI-A-1 · 1.6x`
- User's actual setup (the concrete case to verify): `eDP-1` at 1.5 (non-preset — exercises D-04), `HDMI-A-1` at 1.6 positioned `-1200x0` (exercises position preservation end-to-end through the panel)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 2-Per-monitor Display panel*
*Context gathered: 2026-09-14*
