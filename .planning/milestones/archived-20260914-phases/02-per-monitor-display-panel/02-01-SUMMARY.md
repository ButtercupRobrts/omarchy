---
phase: 02-per-monitor-display-panel
plan: 01
subsystem: ui
tags: [quickshell, qml, hyprland, jq, per-monitor-scaling, panel]

requires:
  - phase: 01-per-monitor-scale-persistence-in-the-scaling-cli
    provides: "omarchy-hyprland-monitor-scaling <SCALE> [monitor] positional contract (verified in 01-VERIFICATION.md)"
provides:
  - "Each bar-hosted omarchy.monitor panel resolves its hosting screen via the QsWindow attached property and aims SCALE pills / setScale at that screen's monitor"
  - "omarchy-monitor-state line-7 displays JSON now carries a per-monitor scale field (8-line positional contract unchanged)"
  - "DISPLAYS rows render name · N.Nx (plus · focused); SCALE header reads ownScreenName · ownScalex with no display-count gate"
  - "Model.scalesWithCurrent: non-preset current scale surfaces as a dynamically inserted, sorted pill that matchingScaleIndex marks active"
affects: [verify-work, uat, phase-3]

actuals:
  tokens: 2200
  tasks: 4
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Own-screen identity via bound QsWindow attached property (ownWindow/ownScreenName), mirroring Bar.qml slotScreenName"
    - "Parallel own* properties alongside focusedMonitor/monitorScale — shared IPC state stays instance-independent"
    - "Direct argv Process.command with conditional arg push (no bash -c, no string interpolation)"
    - "Sorted-insert helper (scalesWithCurrent) composing matchingScaleIndex/normalizeScale for dynamic pill injection"

key-files:
  created: []
  modified:
    - bin/omarchy-monitor-state
    - shell/plugins/panels/monitor/Panel.qml
    - shell/plugins/panels/monitor/Model.js
    - test/shell.d/monitor-state-test.sh
    - test/shell.d/monitor-test.sh

key-decisions:
  - "ownScreenName is a readonly bound property (never snapshotted) so it re-evaluates when QsWindow attaches after Component.onCompleted"
  - "ownDisplay() name-matches ownScreenName and falls back to the focused row while the name is empty or absent from the JSON"
  - "focusedMonitor/monitorScale keep focused-monitor semantics for brightness argv and stateIpc; own* properties are parallel, never repurposed"
  - "setScale builds [omarchy-hyprland-monitor-scaling, scale] argv and appends ownScreenName only when non-empty (empty degrades to the CLI's focused-default)"
  - "SCALE header single-monitor form: `SCALE — <name> · N.Nx` — the enabledDisplayCount gate dropped entirely (D-03 discretion)"
  - "DISPLAYS row scale suffix gated on display.enabled AND non-empty normalizeScale — disabled/stale rows render name-only (D-01/D-02)"

patterns-established:
  - "QsWindow attached property is the only per-screen discriminator for bar-hosted widget instances (injected `bar` is a shared root)"
  - "Dynamic pill row: insert normalized current value into the preset ladder, let matchingScaleIndex mark it active — no new state tracking"
  - "Textual QML assertions (fs.readFileSync + regex extraction + includes pinning) cover runtime bindings that cannot run headless"

requirements-completed: [SCALE-05, SCALE-06, SCALE-07]

coverage:
  - id: D1
    description: "omarchy-monitor-state emits per-monitor scale as the last field of each line-7 JSON object; 8-line positional contract byte-stable"
    requirement: SCALE-06
    verification:
      - kind: unit
        ref: "test/shell.d/monitor-state-test.sh (all four fixtures, byte-for-byte line-7 assertions)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Model.scalesWithCurrent inserts a non-preset current scale in numeric order and matchingScaleIndex marks it active; preset-matching values add no pill"
    requirement: SCALE-05
    verification:
      - kind: unit
        ref: "test/shell.d/monitor-test.sh#scalesWithCurrent cases"
        status: pass
      - kind: other
        ref: "node -e require + sorted-insert check → [\"1\",\"1.25\",\"1.5\",\"1.6\",\"2\",\"3\",\"4\"]"
        status: pass
    human_judgment: false
  - id: D3
    description: "Panel targets the hosting screen: ownScreenName/ownDisplay/ownScale drive scaleValues/activeScaleIndex/effectiveScale/setScale argv; SCALE header and DISPLAYS row suffix render per-monitor values; single-monitor form works"
    requirement: SCALE-05
    verification:
      - kind: unit
        ref: "test/shell.d/monitor-test.sh (textual QML assertion block)"
        status: pass
      - kind: manual_procedural
        ref: "user UAT checklist in 'Issues Encountered' — QsWindow/screen bindings need a live shell"
        status: unknown
    human_judgment: true
    rationale: "own-screen resolution is a runtime QsWindow attached-property binding; textual assertions pin structure but only a running multi-monitor shell proves eDP-1 vs HDMI-A-1 targeting, pill rendering, and persistence end-to-end"

duration: 24min
completed: 2026-09-14
status: complete
---

# Phase 2 Plan 01: Per-monitor Display panel Summary

**Each bar's monitor panel now resolves its hosting screen via `QsWindow` and aims SCALE pills, `setScale`, the section header, and DISPLAYS row scale suffixes at that screen's own monitor — with a one-word `scale` addition to `omarchy-monitor-state`'s line-7 JSON and a dynamic pill for non-preset scales.**

## Performance

- **Duration:** 24 min
- **Started:** 2026-09-14T13:21:00Z
- **Completed:** 2026-09-14T13:45:00Z
- **Tasks:** 4
- **Files modified:** 5

## Accomplishments

- `bin/omarchy-monitor-state` line-7 jq projection now emits `scale` per monitor object — one word, 8-line positional contract untouched (D-06)
- `Panel.qml` gains bound `ownWindow`/`ownScreenName` (QsWindow-sourced), `ownDisplay()` with focused fallback, and `ownScale`; `scaleValues`/`activeScaleIndex`/`effectiveScale` re-pointed at the own display while `focusedMonitor`/`monitorScale` keep focused semantics for brightness + IPC
- `setScale` dropped `bash -c` for direct argv (`["omarchy-hyprland-monitor-scaling", scale]` + conditional `ownScreenName` push), keeping the `!actionProc.running` guard — panel-initiated changes now persist to the right `hl.monitor()` line via the Phase 1 CLI
- SCALE header reads `ownScreenName · ownScalex` whenever the screen is known (D-03); DISPLAYS rows render `name · N.Nx` before `· focused`, gated on `enabled` + non-empty normalization (D-01); all `displays.length > 1` gates untouched (SCALE-07)
- `Model.scalesWithCurrent` sorted-inserts a non-preset current scale so e.g. `eDP-1` at 1.5 shows a highlighted `1.5` pill among the presets (D-4)
- 6 new Node cases + 16 textual QML assertions pin the contract headlessly

## Task Commits

Each task was committed atomically:

1. **Task 1 (tracer): own-screen targeting slice** — `73dc2628` (feat) — jq `scale` field, fixture + byte-for-byte assertion updates, `ownWindow`/`ownScreenName`/`ownDisplay()`/`ownScale`, re-pointed scale lookups, argv `setScale`, header + row suffix
2. **Task 2: dynamic "current" pill** — `44ef1ffd` (feat) — `scalesWithCurrent` helper + `module.exports`, `scaleValues` wrap, 6 Node cases
3. **Task 3: textual QML assertions** — `ad71328d` (test) — second `run_node_test` block pinning own-screen sourcing, argv shape, header binding, row suffix order, single displays-JSON path
4. **Task 4: regression sweep + verification** — no code commit; sweep results below, visual UAT documented for the user

**Plan metadata:** `docs(02-01)` commits follow this summary.

## Verification Results

- `bash -n bin/omarchy-monitor-state` — exit 0
- `bash test/shell.d/monitor-state-test.sh` — all `ok -`, byte-for-byte line-7 assertions pass
- `bash test/shell.d/monitor-test.sh` — all `ok -` (42 assertions)
- `bash test/shell.d/monitor-scaling-test.sh` — all `ok -` (36 cases; Phase 1 contract intact)
- `./test/cli` — exit 0 (metadata lint unaffected)
- `./test/shell` — **only the 7 known environmental failures** (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths); no new failures
- `! grep -n '"bash", "-c"' Panel.qml` — clean; `root.focusedMonitor` remains only at stateIpc (:226), brightness argv (:259), and line-5 parse (:420)
- `git diff 57e6b9ca..HEAD --stat` — exactly the five `files_modified` paths across the three task commits

## Files Created/Modified

- `bin/omarchy-monitor-state` — `scale` added to the line-7 per-monitor jq projection (`{name, enabled, focused, width, height, scale}`); all other lines/ordering unchanged (D-06)
- `shell/plugins/panels/monitor/Panel.qml` — `ownWindow`/`ownScreenName` bound properties, `ownScale`, `ownDisplay()`; `scaleValues`/`activeScaleIndex`/`effectiveScale` re-pointed + `scalesWithCurrent` wrap; `setScale` direct argv; `scaleMonitor` header per D-03; `MonitorRow` name text `· N.Nx` suffix per D-01 (targeted edits only — Nerd Font glyphs preserved)
- `shell/plugins/panels/monitor/Model.js` — `scalesWithCurrent` sorted-insert helper (ES5 style) added to `module.exports`
- `test/shell.d/monitor-state-test.sh` — `scale` added to all four fixtures; both byte-for-byte line-7 assertions updated
- `test/shell.d/monitor-test.sh` — `scalesWithCurrent` Node coverage + textual QML assertion block

## Decisions Made

- `ownScreenName` is a **bound** `readonly property` — `Component.onCompleted: refresh()` can fire before `QsWindow` attaches; a snapshot would stay `""` forever
- `ownDisplay()` returns the `name === ownScreenName` row with the focused row as fallback while the name is `""` or absent — pill row never renders empty mid-bind
- `ownScale` normalizes `ownDisplay().scale`, falling back to `monitorScale` when the own display is unresolved or normalizes empty — the header never prints `· x`
- `setScale` omits the monitor arg when `ownScreenName === ""`, degrading to the CLI's focused-default
- Single-monitor header form (D-03 discretion): `SCALE — <name> · N.Nx` — dropped the `enabledDisplayCount > 1` gate entirely
- Mirror-target no-op accepted per Flagged Assumptions (CLI drops mirror outputs; `actionProc` completes → `refresh()` only)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `scalesWithCurrent` empty-scale guard hardened beyond the PATTERNS snippet**
- **Found during:** Task 2 (`scalesWithCurrent` helper)
- **Issue:** The PATTERNS.md shape guarded with `Number(normalizeScale(currentScale))` + `isFinite` — but `Number("")` is `0` (finite), so an empty/invalid `currentScale` would have spliced an empty-string pill at index 0. The plan's action text explicitly requires returning `scales` unchanged when `normalizeScale(currentScale)` is non-finite/empty.
- **Fix:** Bind `normalized = normalizeScale(currentScale)` once and guard on `normalized === "" || !isFinite(current)`; splice `normalized` (not a recomputed call).
- **Files modified:** `shell/plugins/panels/monitor/Model.js`
- **Verification:** New `''`/`'nope'` identity cases in `monitor-test.sh` pass; insertion cases unaffected.
- **Committed in:** `44ef1ffd` (Task 2 commit)

### Process adaptation (not a code deviation)

**2. Per-task atomic commits instead of task-4's single commit**
- Plan task 4 action 3 reads "commit all five `files_modified` paths as ONE atomic commit"; the sequential execution contract requires one coherent change per task commit. Tasks 1–3 each committed their slice; `git diff <base>..HEAD --stat` confirms exactly the five `files_modified` paths and nothing else. The "one coherent unit" intent is preserved — the three commits are consecutive and adjacent.

---

**Total deviations:** 1 auto-fixed bug + 1 process adaptation
**Impact on plan:** The guard fix is required for the stated contract (empty currentScale must not add a pill). No scope creep.

## Issues Encountered

- **Visual verification deferred to user UAT.** Plan task 4 step 2 requires a live-shell check, but the running shell loads the packaged `/usr/share/omarchy` tree — restarting it would not load these changes, and driving bar panels in the user's session isn't feasible from an agent. No shell restart was performed. Manual UAT checklist for the user once the changes are deployed (`omarchy dev link` / package update) and `omarchy-restart-shell` has run:
  1. Open the monitor panel on each screen's bar (click the bar widget on `eDP-1` and on `HDMI-A-1`; `omarchy-shell shell summon omarchy.monitor` lands on the focused screen's instance).
  2. `omarchy capture screenshot fullscreen save` for each — verify each panel's SCALE header shows ITS OWN monitor (`SCALE — eDP-1 · 1.5x` on the laptop bar, `SCALE — HDMI-A-1 · 1.6x` on the Samsung bar).
  3. Confirm eDP-1's row shows the dynamic `1.5` pill highlighted among the presets.
  4. Confirm DISPLAYS rows read `name · N.Nx` with `· focused` on the focused row.
  5. Click a pill on the HDMI bar; `hyprctl monitors -j` should report HDMI-A-1's scale changed while eDP-1's did not; the pill row should reflow 7→6 cleanly after applying a preset.
  6. Exercise h/l + Enter via `wtype` for keyboard nav.
  7. Check a `monitors.lua` line for HDMI-A-1 was written by the Phase 1 CLI (persistence end-to-end).
- No other issues — all focused suites green on first run.

## User Setup Required

None — no external service configuration required. (Running-UI verification above is UAT, not setup.)

## Next Phase Readiness

- Phase 2's single plan is executed; the milestone's two-phase scope (CLI persistence + per-monitor panel) is code-complete pending user UAT of the visual items above.
- Housekeeping noted by the plan: the stale `REQUIREMENTS.md` Out-of-Scope row ("Panel reads `hyprctl monitors -j` itself") is superseded by D-06 — a planning-artifact correction owned by the phase-transition step, not this plan.
- Blocker for upstreaming/verify-work: the own-screen targeting path is only textually pinned until the UAT checklist runs on the live dual-monitor setup.

## Self-Check: PASSED

- All five `files_modified` paths exist and match the diff stat (`git diff 57e6b9ca..HEAD`)
- `git log --oneline 57e6b9ca..HEAD` returns the three task commits
- All `<acceptance_criteria>` re-run and passing (grep pins, `bash -n`, both monitor suites, `./test/cli`, `./test/shell` failure set matches the 7 known)
- Pre-existing `M bin/omarchy-capture-text` and untracked `.planning/state.json` left untouched

---
*Phase: 02-per-monitor-display-panel*
*Completed: 2026-09-14*
