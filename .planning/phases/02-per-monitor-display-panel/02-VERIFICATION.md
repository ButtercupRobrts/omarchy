---
status: verified
date: 2026-09-14
verified_by: gsd-verifier
scope: git diff 57e6b9ca..HEAD (tasks 73dc2628, 44ef1ffd, ad71328d + review fix 19df93db)
---

# Phase 2 Verification: Per-monitor Display panel

## Goal achieved?

**Yes — VERIFIED.** `shell/plugins/panels/monitor/` now resolves each bar instance's own screen via the `QsWindow` attached property (`Panel.qml:35-36`), aims the SCALE pills / `setScale` / section header at that screen's monitor, and shows each monitor's current scale in the DISPLAYS section (`Panel.qml:915`). `bin/omarchy-monitor-state` still emits exactly 8 lines — confirmed by running it live in this environment (`hyprctl` present): line 7 JSON objects carry `scale` as the new last field; all other lines and ordering are unchanged.

The one Warning from `02-REVIEW.md` (header could render `NAME · x` while `ownScale` is empty) is fixed in `19df93db`: `scaleMonitor.visible` is now `root.ownScreenName !== "" && root.ownScale !== ""` (`Panel.qml:776`), with the matching textual assertion updated in `monitor-test.sh`.

## Requirement coverage

| Req | Status | Evidence |
|-----|--------|----------|
| SCALE-05 | Covered (code) + human-verify (visual) | `ownWindow`/`ownScreenName` bound properties (`Panel.qml:35-36`), `ownDisplay()` name-match with focused fallback (`:283-292`), `scaleValues`/`activeScaleIndex`/`effectiveScale` re-pointed (`:61-64`, `:294-302`), `setScale` direct argv with conditional monitor arg (`:325-330`), dynamic pill via `Model.scalesWithCurrent` (`Model.js:82-100`, exported `:141`) |
| SCALE-06 | Covered | `omarchy-monitor-state:22-23` jq projection emits `scale`; DISPLAYS row renders `name · N.Nx` before `· focused`, gated on `enabled` + non-empty `normalizeScale` (`Panel.qml:915`); click still runs only the stock enable/disable toggle (`:945`) |
| SCALE-07 | Covered | All three `displays.length > 1` gates untouched (`:92`, `:814`, `:821`); SCALE header has no display-count gate — single-monitor form is `SCALE — <name> · N.Nx` (`:775-776`) |

`REQUIREMENTS.md` accounts for all three: SCALE-05/06/07 are `[x]` and mapped to Phase 2 / Complete (`:19-21`, `:50-52`). One stale Out-of-Scope row (`:40`, "Panel reads `hyprctl monitors -j` itself") is superseded by the promoted D-06 decision — known housekeeping item for phase transition, documented in the plan and summary; not a code gap.

## must_haves check

Truths — all confirmed against code:

- Per-instance screen resolution via `root.QsWindow.window.screen.name`, bound not snapshotted (`:35-36`) — SCALE pills, `setScale`, and header target the hosting screen's monitor.
- `setScale` builds `["omarchy-hyprland-monitor-scaling", String(scale)]`, pushes `ownScreenName` only when non-empty, keeps `if (!actionProc.running) actionProc.running = true` verbatim (`:325-330`). No `bash -c`, no interpolation.
- SCALE header text `ownScreenName + " · " + ownScale + "x"`, no `enabledDisplayCount`/`displays.length` gate (`:775-776`).
- DISPLAYS row suffix order name → `· N.Nx` → `· focused`, gated on `enabled && normalizeScale(scale) !== ""` — disabled/missing-scale rows render name-only (`:915`).
- Non-preset current scale inserts as a sorted pill marked active by `matchingScaleIndex`; preset-matching adds no pill (`Model.js:82-100`; node check prints `["1","1.25","1.5","1.6","2","3","4"]`).
- Single-monitor: no DISPLAYS section/separator (`displays.length > 1` gates intact); SCALE row and keyboard nav unchanged.
- `omarchy-monitor-state` emits 8 lines, same order; only line-7 objects gained `scale` — verified by executing the script (live `hyprctl`, output shown above).
- `focusedMonitor`/`monitorScale` keep focused semantics: `stateIpc` (`:226-227`), brightness argv (`:259`), lines 5/6 parsing (`:420-421`) — `grep` confirms `root.focusedMonitor` only at those sites.

Prohibitions — all respected:

- `focusedMonitor`/`monitorScale` not repurposed; parallel `own*` properties added instead.
- Panel.qml edits are targeted hunks; Nerd Font glyphs preserved (`:492`, `:555`, `:904`, `:926`).
- `grep '"bash", "-c"' Panel.qml` → no matches.
- `ownScreenName` is a `readonly` bound property.
- 8-line positional contract byte-stable (fields inside line-7 JSON only).
- `actionProc` re-spawn guard kept (`:329`).
- No `hyprctl monitors -j` (non-`all`) anywhere for display rows; the script uses `hyprctl monitors all -j` (`bin/omarchy-monitor-state:6`); the only panel `hyprctl` argv is the pre-existing `toggleDisplay` `keyword monitor` call (`:321`).
- No click action or new affordance added to the row's scale text.
- No second state Process — still 4 `Process {}` blocks (stateProc, setBrightnessProc, actionProc, textScaleProc).
- No display-count gate on SCALE header or pill targeting.

## Test results

| Check | Result |
|-------|--------|
| `bash test/shell.d/monitor-state-test.sh` | PASS — all `ok -`, exit 0 (byte-for-byte line-7 assertions include `"scale"`) |
| `bash test/shell.d/monitor-test.sh` | PASS — all `ok -`, exit 0 (43 assertions incl. 6 `scalesWithCurrent` cases + 16 textual QML pins) |
| `bash test/shell.d/monitor-scaling-test.sh` | PASS — all `ok -`, exit 0 (Phase 1 `[monitor]` arg contract intact) |
| `bash -n bin/omarchy-monitor-state` | PASS — exit 0 |
| `! grep '"bash", "-c"' Panel.qml` | PASS — absent |
| `node -e` scalesWithCurrent sorted-insert | PASS — `["1","1.25","1.5","1.6","2","3","4"]` |
| `./test/cli` | PASS — exit 0 |
| `bash bin/omarchy-monitor-state` (live) | PASS — exactly 8 lines, `scale` last field per object |

## Known issues / human-verify items

- **Per-bar visual targeting cannot be verified headlessly** — `QsWindow` attached-property resolution, per-screen header text, dynamic-pill highlight, and end-to-end persistence require the live shell with the changes deployed (`omarchy dev link` / package update + `omarchy-restart-shell`). User UAT checklist (from `02-01-SUMMARY.md`):
  1. Open the monitor panel on each screen's bar (click the bar widget on `eDP-1` and on `HDMI-A-1`; `omarchy-shell shell summon omarchy.monitor` lands on the focused screen's instance).
  2. `omarchy capture screenshot fullscreen save` for each — verify each panel's SCALE header shows ITS OWN monitor (`SCALE — eDP-1 · 1.5x` vs `SCALE — HDMI-A-1 · 1.6x`).
  3. Confirm eDP-1's row shows the dynamic `1.5` pill highlighted among the presets.
  4. Confirm DISPLAYS rows read `name · N.Nx` with `· focused` on the focused row.
  5. Click a pill on the HDMI bar; `hyprctl monitors -j` should report HDMI-A-1's scale changed while eDP-1's did not; pills reflow 7→6 cleanly after applying a preset.
  6. Exercise h/l + Enter via `wtype` for keyboard nav.
  7. Check a `monitors.lua` line for HDMI-A-1 was written by the Phase 1 CLI (persistence end-to-end).
- **Mirror-target no-op** — pills on a mirrored screen's bar silently no-op (the CLI drops mirror outputs). Accepted per the plan's Flagged Assumptions; worth a spot-check on real hardware during UAT.
- **Review Info items** (8, all judged acceptable to leave): out-of-range dead pill, non-mode-clean scale edge, unreachable disabled-own-display path, pre-existing `actionProc` argv overwrite, mirror no-op, formatting-brittle textual assertions, implicit ascending-input assumption in `scalesWithCurrent`, headless coverage gap in `own-*` fallback semantics. None block the goal; all are documented in `02-REVIEW.md`.
- Stale `REQUIREMENTS.md:40` Out-of-Scope row (panel reading `hyprctl` itself) is superseded by D-06 — planning-artifact cleanup owned by the phase-transition step.
