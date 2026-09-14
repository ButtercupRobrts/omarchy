---
phase: 03-scale-aware-monitor-position-adjustment
plan: 01
subsystem: cli
tags: [bash, hyprland, jq, awk, per-monitor-scaling, monitor-layout, lua-rewrite]

requires:
  - phase: 01-per-monitor-scale-persistence-in-the-scaling-cli
    provides: "omarchy-hyprland-monitor-scaling scale/monitor persistence to hl.monitor() rules, audit TSV, clean_scale ladder"
  - phase: 02-per-monitor-display-panel
    provides: "per-monitor panel calling this CLI with an explicit monitor argument (inherits this fix unchanged)"
provides:
  - "recompute_monitor_position: pure monitors-JSON + target + new-scale → 'XxY kind dropped' (kind ∈ unchanged|adjacency|clamp|abort)"
  - "edge-adjacent monitors (touching or within ~5 logical px, either direction) stay touching after scale changes; deliberate gaps and single-monitor layouts keep live coordinates verbatim"
  - "new-overlap fail-safes: minimal separating clamp for non-adjacent growth, in-band abort to live coords when no safe position exists"
  - "atomic scale+position(+transform) hyprctl eval, single verify-read, and audit pos=/note= fields appended at line end"
  - "in-place position persistence on the target's own hl.monitor() rule via a descending-offset edit list; auto* skipped, var-refs rewritten, missing keys never inserted"
  - "omarchy_gdk_scale = round-half-up of max(all live monitor scales + target's new scale)"
affects: [verify-work, uat]

actuals:
  tasks: 4
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Pure jq→TSV→awk geometry pipeline inside a sourceable function — no filesystem, no hyprctl, return-status only"
    - "Single monitors fetch feeding target lookup, geometry recompute, verify-read, and the GDK max — one hyprctl monitors -j per set_scale"
    - "Descending-offset edit list: all splice spans computed against untouched block_nostr, applied highest-first"
    - "ENVIRON channels for untrusted text (monitor identity, OMARCHY_NEW_POSITION); -v reserved for trusted numerics"
    - "In-band abort contract: '<live>x<live> abort -' at status 0 — non-zero reserved for unusable input"

key-files:
  created: []
  modified:
    - bin/omarchy-hyprland-monitor-scaling
    - test/shell.d/monitor-scaling-test.sh

key-decisions:
  - "Adjacency tolerance ~5 logical px on BOTH axes, in either direction (tiny gap or tiny overlap) — D-01/D-02"
  - "Sandwich resolution keeps the adjacency with the largest shared boundary; ties keep the target's own top-left edge fixed (minimal-move reading of 'prefer left/top'), sacrificed sides recorded as drop-<side> audit tokens — D-03"
  - "Any recompute producing a new positive-area overlap discards the position change entirely — live coords apply, note=abort logged — D-04"
  - "Non-adjacent growth gets the smallest separating move along the shared axis — D-05; deliberate gaps (>5px) are preserved byte-exact — D-06"
  - "One atomic scale+position eval then one verify-read (|Δ| < ~0.006 → note=scale-divergence) — D-07"
  - "Position persists only when it differs from live AND the stored value is not auto*; missing position is never inserted — D-08 + promoted Q4 refinement"
  - "omarchy_gdk_scale = int(0.5 + max(new_scale, other monitors' .scale)) — round-half-up, never ceil — D-09"

patterns-established:
  - "recompute_monitor_position output contract: 'XxY kind dropped' — kind classifies the outcome, dropped lists sacrificed adjacency sides for audit"
  - "Transform-aware logical dims: odd .transform swaps width/height before scale division, for target AND neighbors; non-zero transform replays in eval and appended rules"
  - "Post-apply verify-read: re-fetch monitors -j once after eval, compare applied vs computed scale with a float tolerance, never string equality"
  - "Test-stub env knobs OMARCHY_TEST_MONITORS_JSON / OMARCHY_TEST_MONITORS_JSON_AFTER_EVAL gate arbitrary layouts and post-eval state through the eval-out marker file"

requirements-completed: [SCALE-08, SCALE-09, SCALE-10]

coverage:
  - id: D1
    description: "recompute_monitor_position truth table: left/right/above/below adjacency, ±1–5px normalization, >5px deliberate gaps, single-monitor, sandwich largest-edge + tie, dedup'd dropped sides, third-monitor abort, minimal clamp, portrait target/neighbor transforms, absent-target rejection"
    requirement: SCALE-08
    verification:
      - kind: unit
        ref: "test/shell.d/monitor-scaling-test.sh sourced-function layer (18 cases, all pinned to exact 'XxY kind dropped' strings)"
        status: pass
      - kind: other
        ref: "bash -c 'source … && recompute_monitor_position …' → -960x0 adjacency - / -1280x0 adjacency - / -768x0 adjacency - (canonical triple)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Atomic apply + audit: scale and recomputed position in one hyprctl eval line, verify-read flags note=scale-divergence, abort/sandwich cases log pos= + note=abort|adjacency,drop-<side> appended after grandparent="
    requirement: SCALE-08
    verification:
      - kind: e2e
        ref: "test/shell.d/monitor-scaling-test.sh stub-hyprctl cases: single-line eval capture, AFTER_EVAL divergence fixture, 4-monitor abort fixture, 3-monitor sandwich fixture"
        status: pass
    human_judgment: false
  - id: D3
    description: "In-place position persistence: position-before-scale and scale-before-position rewrites, auto skip, var-ref rewrite, multi-line rule, unchanged-position no-churn — all against the descending-offset edit list; appended rules stay single-line and carry transform"
    requirement: SCALE-09
    verification:
      - kind: e2e
        ref: "test/shell.d/monitor-scaling-test.sh monitors.lua fixture cases (7 persistence cases) + transform append pin"
        status: pass
    human_judgment: false
  - id: D4
    description: "omarchy_gdk_scale derives from the densest monitor: target 1.25 beside a 1.6 monitor still writes 2; max 1.25 writes 1; single-monitor behavior unchanged"
    requirement: SCALE-10
    verification:
      - kind: e2e
        ref: "test/shell.d/monitor-scaling-test.sh mixed-monitor and max-1.25 cases pinning the lua env line"
        status: pass
    human_judgment: false
  - id: D5
    description: "Live-layout end state on real hardware: adjacent monitors neither drift apart nor overlap after scale changes, hyprctl reload cannot recreate a gap"
    requirement: SCALE-08
    verification:
      - kind: manual_procedural
        ref: "user UAT checklist in 'Issues Encountered' — needs a live multi-monitor Hyprland session"
        status: unknown
    human_judgment: true
    rationale: "geometry is proven against stub JSON and exact-position pins, but only a real multi-monitor session exercises Hyprland's own edge rounding and the reload-after-persist path end-to-end"

completed: 2026-09-14
status: complete
---

# Phase 3 Plan 01: Scale-aware Monitor Position Adjustment Summary

**`omarchy-hyprland-monitor-scaling` now recomputes the target monitor's position whenever a scale change alters its logical size — keeping edge-adjacent monitors touching, preserving deliberate gaps byte-exactly, clamping or aborting anything that would create a new overlap — applies scale+position in one atomic `hyprctl eval`, persists the corrected `position = "XxY"` in place on the target's own `hl.monitor()` rule, and derives `omarchy_gdk_scale` from the densest connected monitor.**

## Performance

- **Completed:** 2026-09-14
- **Tasks:** 4
- **Files modified:** 2

## Accomplishments

- `recompute_monitor_position` — a pure jq→TSV→awk pipeline (RESEARCH Q5 spec): logical dims = round(pixel/scale) with odd-`transform` axis swap for target and neighbors; edge candidates on both axes within the 5px tolerance (D-01/D-02); largest-shared-boundary pick with own-top-left tie-break and `drop-<side>` tokens for sacrificed adjacencies (D-03); verbatim keep for deliberate gaps and zero-candidate layouts (D-06); minimal separating clamp for non-adjacent growth (D-05); in-band `abort` to live coords whenever the result would create a new positive-area overlap (D-04)
- `set_scale` fetches `hyprctl monitors -j` once and feeds target lookup, recompute, verify-read, and the GDK max from it — no `monitors all` (phantom mirror boxes), no second pre-eval fetch
- Scale and recomputed position (plus `transform` when non-zero) apply in ONE `hl.monitor({...})` eval — the intermediate-frame gap flash is structurally impossible (D-07); a single post-eval verify-read appends `note=scale-divergence` when the applied scale diverges by ≥ ~0.006
- `audit_scale_change` gained optional `pos=`/`note=` arguments appended at TSV line END — every existing field through `grandparent=` untouched
- `persist_monitor_scale` rewrote the in-place splicer as a collected edit list: scale + position spans compute against untouched `block_nostr`, apply descending-offset — no stale-offset corruption; `position` rewrites only when changed and non-`auto*`, var-refs rewrite to literals, missing keys never insert, both key orders and multi-line rules handled; `OMARCHY_NEW_POSITION` reaches awk via `ENVIRON` only
- `omarchy_gdk_scale` is now `int(0.5 + max(all monitor scales + target's new scale))` — scaling a secondary monitor can never write a lower factor than the densest display needs (D-09)
- `BASH_SOURCE` dispatch guard makes the script sourceable; `recompute_monitor_position` never `exit`s, never touches the filesystem or hyprctl
- Test stub grew `OMARCHY_TEST_MONITORS_JSON` (arbitrary layouts), `OMARCHY_TEST_MONITORS_JSON_AFTER_EVAL` (post-eval state), and `transform` fixture fields; suite went 36 → 67 assertions

## Task Commits

Each task was committed atomically:

1. **Task 1 (tracer): recompute + atomic eval slice** — `20b8feb1` (feat) — `recompute_monitor_position`, single-fetch `set_scale`, transform read/replay, atomic eval, verify-read, audit `pos=`/`note=`, `BASH_SOURCE` guard, stub knobs + `source` unit layer, re-pointed `-768x0`/`-960x0` expectations
2. **Task 2: in-place position persistence** — `b2b14c50` (feat) — descending-offset edit list, `OMARCHY_NEW_POSITION` env channel, `auto*`/missing-key skips, var-ref rewrite, both key orders + multi-line fixtures
3. **Task 3: densest-monitor GDK scale** — `7dafa873` (feat) — `max(new_scale, other scales)` rounded half-up, mixed-monitor + max-1.25 cases
4. **Task 4: truth table + e2e coverage** — `efc7797c` (test) — 14 geometry cases (all four sides, ±tolerance boundary, sandwich/tie/dedup, abort, clamp, transforms, float noise, absent target) + 5 e2e cases (atomic eval, divergence audit, abort audit, drop-side audit, transform replay/persist)

**Plan metadata:** this `docs(03-01)` commit follows the task commits.

## Verification Results

- `bash -n bin/omarchy-hyprland-monitor-scaling` — exit 0
- `bash test/shell.d/monitor-scaling-test.sh` — **67 `ok -`, 0 `not ok`** (baseline before this plan: 36)
- `bash test/shell.d/monitor-clamshell-scale-test.sh` — 25 `ok -`, 0 `not ok`
- `bash test/shell.d/monitor-state-test.sh` — 5 `ok -`, 0 `not ok`
- `bash test/shell.d/monitor-test.sh` — 42 `ok -`, 0 `not ok`
- `bash test/shell.d/monitor-output-name-test.sh` — 8 `ok -`, 0 `not ok`
- `./test/cli` — all `ok -`, exit 0
- `./test/shell` — **7 of 236 files failed, exactly the known environmental set** (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths); zero delta
- Canonical check: `source … && recompute_monitor_position '<2-monitor JSON>' HDMI-A-1 2` → `-960x0 adjacency -` (plus `-1280x0`@1.5, `-768x0`@2.5 via the e2e fixture)
- `rg 'monitors all' bin/omarchy-hyprland-monitor-scaling` — no match
- No literal `position = "auto"` emitted; `pos=`/`note=` appear only at TSV line end (pinned by `grep -E '\tpos=0x0\tnote=scale-divergence$'`)
- `git diff 38a5dd94..HEAD --stat` — exactly the two `files_modified` paths across the four task commits

## Files Created/Modified

- `bin/omarchy-hyprland-monitor-scaling` — `recompute_monitor_position` (pure), single-fetch `set_scale` with transform read, atomic eval + verify-read, `audit_scale_change` `pos=`/`note=` tail fields, `persist_monitor_scale` edit-list + `OMARCHY_NEW_POSITION` + transform on appended rules, max-of-monitors `new_gdk_scale`, `BASH_SOURCE` dispatch guard
- `test/shell.d/monitor-scaling-test.sh` — stub env knobs + `transform` fixture fields, sourced unit layer with the full geometry truth table, five `write_*_config` persistence fixtures, atomicity/verify-read/audit/transform e2e cases, re-pointed external-monitor expectations

## Decisions Made

- Implemented D-01..D-09 as locked; the two promoted refinements from the plan's assumption-delta stand: **`auto*` positions are never written and a missing `position` is never inserted** (auto-derived positions can't go stale — D-08's rewrite covers only the literal that can), and **D-03's tie-break is the minimal-move reading** — the target keeps its own top-left edge (`right-of`/`below` candidates win ties), verified by the `0x0 adjacency left-of` pinned case.
- Abort is in-band (`<live> abort -`, status 0): a recompute that can't place safely is a defined outcome the caller logs, not a failure — non-zero status stays reserved for unusable input like an absent target.
- The verify-read reuses the eval-out marker in the stub to serve post-eval JSON; applied-vs-computed comparison uses `|Δ| < ~0.006`, never string equality.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Awk comments containing apostrophes broke shell quoting (twice)**
- **Found during:** Task 1 (`recompute_monitor_position` syntax check) and Task 2 (`persist_monitor_scale` edit-list syntax check)
- **Issue:** Comments like `# target's …` inside single-quoted awk programs terminated the shell string → `syntax error near unexpected token`.
- **Fix:** Reworded both comments to drop the apostrophe; no code changed.
- **Files modified:** `bin/omarchy-hyprland-monitor-scaling`
- **Verification:** `bash -n` clean; direct recompute invocation and full suite green.
- **Committed in:** `20b8feb1`, `b2b14c50`

### Deferred (per plan, not regressions)

- Cascading shifts of non-target monitors, `auto-*` position emission, and ceil-based GDK rounding remain explicitly out of scope (D-03/Q4/D-09).

---

**Total deviations:** 1 auto-fixed bug (two instances, same class)
**Impact on plan:** None — comment wording only; the specified algorithm, contracts, and prohibitions are intact.

## Issues Encountered

- **Live-layout verification deferred to user UAT.** The geometry is pinned against stub JSON (exact `XxY` strings) and the eval/persist paths are byte-checked, but Hyprland's own edge rounding and the `hyprctl reload`-after-persist path need a real multi-monitor session. Manual checklist once deployed (`omarchy dev link` / package update):
  1. `omarchy hyprland monitor scaling 1.5 HDMI-A-1` on a setup where HDMI-A-1's edge touches eDP-1 — cursor should traverse the boundary with no dead zone; `hyprctl monitors -j` shows edges touching exactly.
  2. Repeat with `2`, `2.5`, and `up`/`down` — the shared edge stays glued in both directions.
  3. `hyprctl reload`, then re-check positions — `monitors.lua`'s persisted `position = "XxY"` must hold the same layout (no gap recreated).
  4. `grep . ~/.local/state/omarchy/monitor-scaling.log` — tail fields read `pos=XxY note=adjacency` (or `clamp`/`abort`/`drop-<side>`/`scale-divergence` as applicable).
  5. A sandwiched or deliberately-gapped layout if available — gap preserved, sacrificed side logged.
- No other issues — all focused suites green; `./test/shell` delta is zero.

## User Setup Required

None — no external service configuration required. (Live-layout check above is UAT, not setup.)

## Next Phase Readiness

- This was the phase's single plan and closes the milestone: CLI persistence (Phase 1) → per-monitor panel (Phase 2) → scale-aware positions (Phase 3). The panel inherits the fix with zero changes.
- Blocker for upstreaming/verify-work: the UAT checklist above is the only unpinned surface (real-compositor edge rounding + reload path).

## Self-Check: PASSED

- Both `files_modified` paths exist and match `git diff 38a5dd94..HEAD --stat`; `git log` shows the four task commits
- All verification commands re-run and passing; `./test/shell` failure set matches the 7 known environmental files exactly
- Pre-existing `M bin/omarchy-capture-text` and untracked `.planning/state.json` / `.gitkeep` left untouched and uncommitted

---
*Phase: 03-scale-aware-monitor-position-adjustment*
*Completed: 2026-09-14*
