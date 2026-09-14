---
status: issues-found
depth: standard
date: 2026-09-14
files_reviewed:
  - bin/omarchy-monitor-state
  - shell/plugins/panels/monitor/Panel.qml
  - shell/plugins/panels/monitor/Model.js
  - test/shell.d/monitor-state-test.sh
  - test/shell.d/monitor-test.sh
---

# Phase 2 Review: Per-monitor Display panel (02-01)

Scope: `git diff 57e6b9ca..HEAD` — the `scale` jq field addition, `ownWindow`/`ownScreenName`/`ownDisplay()`/`ownScale` targeting, `scalesWithCurrent` dynamic pill, direct-argv `setScale`, header and row suffix bindings, plus both test files. No source or test files were modified by this review.

## Verdict

No Critical findings. One Warning (cosmetic, contradicts a flagged assumption) and several Info observations. Implementation matches the plan's must_haves and respects every prohibition checked. Both focused test suites run green (`monitor-state-test.sh`, `monitor-test.sh` — all `ok -`, exit 0; `bash -n bin/omarchy-monitor-state` clean).

## Verified correct

- **`root.QsWindow` exists on the root Item.** `Panel` (the root type, `shell/Ui/Panel.qml:9`) is an `Item`, and each widget instance is created inside a per-screen `BarPanel` window, so the `QsWindow` attached property resolves to the hosting bar window — the identical source to `Bar.qml:380-382` (`targetWindow` → `target.QsWindow.window`) feeding `slotScreenName` (`Bar.qml:708-711`). The bound-property-on-attach pattern is already proven live in-tree by `KeyboardPanel.qml:66` (`readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null`).
- **Binding freshness.** QML tracks dependencies transitively through function calls, so `ownScale` (`Panel.qml:39-44`), `scaleValues` (:61-64), `activeScaleIndex` (:294-297), `effectiveScale` (:299-302), and the pill `active`/`text` bindings (:857, :865) all re-evaluate when `updateDisplays` reassigns `root.displays` on each `stateProc` poll (:311-315, :422) and when `monitorScale` changes (:421). `ownScreenName` stays a binding, so a pre-attach `Component.onCompleted: refresh()` heals on attach (:372).
- **Fallback logic.** `ownDisplay()` (:283-292) name-matches only when `ownScreenName !== ""`, returns the first exact match even when a focused row precedes it, and falls back to the focused row otherwise. Empty-name consumers all degrade correctly: `setScale` omits the monitor arg → CLI focused-default (:325-330); `scaleMonitor` hides (:776); pill math falls back to focused dims.
- **Focused semantics preserved.** `focusedMonitor`/`monitorScale` still feed brightness argv (:259), `stateIpc` (:226-227), and lines 5/6 (:420-421) — `state()` output is not instance-dependent. `enabledDisplayCount` is used only by the toggle paths (:319, :883); no SCALE-header or pill targeting gates on display count.
- **Contract + security.** Line 7 keeps `jq -c` field order `name, enabled, focused, width, height, scale` (`bin/omarchy-monitor-state:22-23`); the 8-line positional contract is untouched and byte-for-byte assertions were updated in the same commit (`monitor-state-test.sh:112-117`). `setScale` builds a direct argv list (`Panel.qml:326-328`) — no shell, no interpolation; `ownScreenName` is compositor-supplied and the CLI re-validates `^[A-Za-z0-9._-]+$` before Lua embedding (`bin/omarchy-hyprland-monitor-scaling:98`). No injection surface.
- **Row suffix.** Gated on `enabled && normalizeScale(...) !== ""` (:915), so disabled rows, missing `scale` fields (`null` → `""`), and zeroed rows render name-only — never `· x`/`· nullx`. Order is name → scale → focused per D-01.
- **Cursor/pill churn.** `onScaleValuesChanged: clampCursor()` (:393) covers the 7→6 reflow after applying a preset; `clampCursor`/`moveCursorH`/`activateCursor` already handle variable `scaleValues.length` (:147-153, :161-196). `scalesWithCurrent` is ES5-conformant (`var`, top-level function, no arrows) and exported (`Model.js:82-100, :141`).

## Findings

### Warning

1. **`scaleMonitor` can render `NAME · x` while `ownScale` is empty** — `Panel.qml:775-776`. `visible` gates only on `ownScreenName !== ""`; `ownScale` falls back to `monitorScale` but nothing guards the case where both are empty (`displays`/`monitorScale` still `""` during the first `stateProc` poll, or persistently when line 6 is empty — no focused monitor or a failing scaling CLI). Result: `eDP-1 · x` painted in the header. The plan's flagged assumption states the fallback exists "so the header never prints `· x`" (`02-01-PLAN.md:276`); that holds only when `monitorScale` is non-empty. Cosmetic and usually transient — the window exists only between widget creation and the first completed poll — but a persistent empty line 6 makes it permanent. Suggested fix: gate `visible` (or the scale portion of `text`) on `root.ownScale !== ""` as well.

### Info

2. **Out-of-range "current" pill can never apply** — `Model.js:82-100`. `scalesWithCurrent` inserts any finite normalized value; a persisted scale outside the CLI's 1–4 acceptance (`bin/omarchy-hyprland-monitor-scaling:582-583`), e.g. 0.67 or 4.5 set via `hyprctl` directly, yields a pill whose click exits 1 → silent `refresh()` via `actionProc.onRunningChanged` (`Panel.qml:455`). Harmless dead pill; no clamp was specified.
3. **Non-mode-clean current scale edge** — `Model.js:82-100` with `Panel.qml:296, :857`. A hyprctl float that normalizes to a value whose `cleanScale` differs from itself (e.g. 1.0666667 → "1.07", which cleans to "1.2" on 1920×1080) inserts a pill labeled by `effectiveScale` ("1.2x") that applies the raw value and is not marked `active`. Requires non-clean persisted scale data; Hyprland-reported scales are already clean in practice.
4. **Disabled own-display is theoretically reachable in `ownDisplay()`** — `Panel.qml:283-292`. Name-match returns before considering `enabled`, so a row with `width/height: 0` would make `cleanScale` return `""` → every pill renders bare `"x"` and `ownScale` could show the row's stale stored scale. Practically unreachable: a disabled output destroys the `BarPanel` subtree (widget + `KeyboardPanel`) before the bindings matter. Noted for completeness.
5. **`setScale` silently drops a command while `actionProc` is running** — `Panel.qml:325-330, :452-456`. `command` is reassigned unconditionally; if `toggleDisplay` or a prior `setScale` is in flight, the new argv is overwritten without a restart and only `refresh()` runs on completion. Pre-existing shape (the old `bash -c` path behaved identically), unchanged by this diff — flagged because the apply path was touched.
6. **Mirror-target no-op** — mirror rows appear in the `monitors all` JSON with valid dims/scale, so pills render and the header names the mirror; but the CLI selects from `hyprctl monitors -j` (non-`all`), which drops mirrors → exit 1 → silent no-op. Accepted per plan (Flagged Assumptions, `02-01-PLAN.md:274`); confirmed consistent with the threat model's residual.
7. **Textual QML assertions are formatting-brittle** — `monitor-test.sh:119-187`. `/function setScale\(scale\) \{([\s\S]*?)\n  \}/` pins exact 2-space indentation; `/id: scaleMonitor[\s\S]*?anchors\.right: parent\.right/` assumes `text`/`visible` precede `anchors.right` in the block; `/text: monitorRow\.display\.name[^\n]*/` assumes the whole row binding stays on one physical line. Reformatting (property reorder, line wrap, reindent) false-fails the suite. Consistent with the repo's established pinning pattern (`app-search-test.sh`) and forward-looking by design; acceptable.
8. **`scalesWithCurrent` assumes ascending input** — `Model.js:92-97`. The sorted-insert scans for the first `Number(out[i]) > current`; a non-monotonic `scales` array would misplace the value. Holds for both call sites (`availableScales` output, presets); the contract is implicit in the signature.
9. **Coverage gap in own-* logic** — `ownDisplay()` fallback ordering, the `ownScreenName !== ""` guard, and `ownScale`'s monitorScale fallback live in `Panel.qml` and are not Node-testable; the textual block pins sourcing/argv/header/suffix but not the fallback semantics. Unavoidable headless; the plan already routes this to live-shell visual verification (UAT checklist in `02-01-SUMMARY.md`).
