---
phase: 04-menu-defaultindex-plumbing
plan: 01
subsystem: ui
tags: [quickshell, qml, dmenu, json-payload, perl, cli-flags, node-tests]

# Dependency graph
requires: []
provides:
  - "`omarchy-menu-select` accepts `--default-index N` after `--` and emits an optional integer `defaultIndex` field in the select-mode JSON payload (absent field = byte-identical payload)"
  - "`MenuModel.dmenuDefaultIndex(payload, optionCount)` — node-testable resolution of the payload field into [0, count-1]"
  - "`Menu.qml openDmenu` initializes `selectedIndex` from the resolved default before `rebuildDisplay()`; Enter activates the pre-highlighted row"
  - "`docs/menu.md` documents the post-`--` menu-args surface including `--default-index`"
affects: [phase-6, transcode-quality-menu, verify-work, uat]

# Actuals (#2632)
actuals:
  tokens: 3142
  tasks: 3
  commits: 1
  plan_head_before: 42e078fbd24f8d28fa2d5a0093327d18ba4cd696

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Optional payload fields are emitted iff the flag was passed (`int($ARGV[n]) if length($ARGV[n] // \"\")`) — the absent key is the back-compat mechanism"
    - "Index resolution lives in MenuModel.js (ES5, guarded module.exports) so node tests cover the whole contract; QML stays thin and delegates"
    - "Stub-omarchy-shell e2e: capture `$4` (the summon payload), then satisfy the selectionFile/doneFile tempfile handshake so the real script under test returns"

key-files:
  created:
    - test/shell.d/menu-select-test.sh
  modified:
    - bin/omarchy-menu-select
    - shell/plugins/menu/Menu.qml
    - shell/plugins/menu/MenuModel.js
    - docs/menu.md
    - test/shell.d/menu-test.sh

key-decisions:
  - "One atomic commit carries the whole flag→payload→cursor path plus tests and docs (plan-mandated: the milestone's only cross-component contract change must be independently revertible)"
  - "defaultIndex is initial-only — setFilter keeps resetting selectedIndex to 0 on first keystroke, now documented in-place (D-05)"
  - "No new QML validation: rebuildDmenuDisplay's existing clamp bounds the value for free (D-04); the helper still floor/NaN-guards so the node contract is complete"

patterns-established:
  - "Post-`--` menu-args case arm with value-required guard, mirroring --width exactly; unknown menu args stay silently ignored (no `*)` arm)"
  - "Source pins extract function bodies via `function name\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}` and assert ordering by indexOf — applied to openDmenu wiring and the setFilter reset"

requirements-completed: [MENU-01]

coverage:
  - id: D1
    description: "`omarchy-menu-select Pick a b c -- --default-index 1` emits \"defaultIndex\":1 in the select-mode payload and returns the selection through the tempfile handshake unchanged"
    requirement: MENU-01
    verification:
      - kind: e2e
        ref: "test/shell.d/menu-select-test.sh#menu select emits the default index in the payload"
        status: pass
      - kind: e2e
        ref: "test/shell.d/menu-select-test.sh#menu select returns the picked row"
        status: pass
    human_judgment: false
  - id: D2
    description: "With no flag, the payload carries no `defaultIndex` key — all 15 verified call sites, `omarchy-menu-file`'s \"$@\" pass-through, and the routed `omarchy menu select` path are byte-identical"
    requirement: MENU-01
    verification:
      - kind: e2e
        ref: "test/shell.d/menu-select-test.sh#menu select omits the default index when the flag was not passed"
        status: pass
      - kind: e2e
        ref: "test/shell.d/menu-select-test.sh#no existing caller passes --default-index yet"
        status: pass
    human_judgment: false
  - id: D3
    description: "`openDmenu` assigns `selectedIndex` from `MenuModel.dmenuDefaultIndex(payload, dmenuOptions.length)` before `rebuildDisplay()` runs, so Enter activates the pre-highlighted row"
    requirement: MENU-01
    verification:
      - kind: unit
        ref: "test/shell.d/menu-test.sh#menu openDmenu source pins (helper call, ordering, no hardcoded 0)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Out-of-range, negative, non-integer, and non-numeric `defaultIndex` values resolve inside [0, count-1] and never wedge the menu"
    requirement: MENU-01
    verification:
      - kind: unit
        ref: "test/shell.d/menu-test.sh#menu.dmenuDefaultIndex cases (11 assertions incl. clamp/floor/NaN/empty)"
        status: pass
      - kind: e2e
        ref: "test/shell.d/menu-select-test.sh#menu select coerces a non-numeric default index to 0"
        status: pass
    human_judgment: false
  - id: D5
    description: "Typing in the filter still resets the highlight to row 0 — initial-only semantics, documented by the D-05 comment in setFilter"
    requirement: MENU-01
    verification:
      - kind: unit
        ref: "test/shell.d/menu-test.sh#menu filter reset keeps the default index initial-only"
        status: pass
    human_judgment: false
  - id: D6
    description: "`--default-index` with no following value exits 1 with `requires a value` on stderr; stdin-fed callers keep their option stream intact"
    requirement: MENU-01
    verification:
      - kind: e2e
        ref: "test/shell.d/menu-select-test.sh#menu select rejects --default-index without a value"
        status: pass
      - kind: e2e
        ref: "test/shell.d/menu-select-test.sh#menu select keeps the stdin option stream intact behind the flag"
        status: pass
    human_judgment: false
  - id: D7
    description: "Row visibly pre-highlighted in the running shell; Enter selects it; out-of-range clamps to last row; typing moves highlight to row 0; stdin-fed menus unaffected"
    requirement: MENU-01
    verification: []
    human_judgment: true
    rationale: "Visual state requires the running shell; the dev shell loads the packaged /usr/share/omarchy tree so the executor cannot reflect working-tree edits — recorded as UAT checklist below"

# Metrics
duration: 51min
completed: 2026-09-15
status: complete
---

# Phase 4 Plan 01: Menu `defaultIndex` plumbing Summary

**`omarchy-menu-select --default-index N` (post-`--`) → optional `defaultIndex` payload field → `openDmenu` pre-highlighted row via node-testable `MenuModel.dmenuDefaultIndex`, byte-identical for every existing caller**

## Performance

- **Duration:** ~51 min
- **Started:** 2026-09-15T08:38:35Z
- **Completed:** 2026-09-15T09:29:53Z
- **Tasks:** 3
- **Files modified:** 6 (1 created)

## Accomplishments

- `bin/omarchy-menu-select` parses `--default-index N` inside the post-`--` loop (value-required guard mirroring `--width`) and emits `defaultIndex` as a JSON integer only when the flag was passed — the absent key keeps all 15 verified call sites, `omarchy-menu-file`'s `"$@"` pass-through, and the routed `omarchy menu select` path byte-identical.
- `MenuModel.dmenuDefaultIndex(payload, optionCount)` resolves the field into `[0, count-1]` with floor/NaN/negative guards, exported through the existing guarded `module.exports`; `openDmenu` stores it in `property int dmenuDefaultIndex` and assigns `selectedIndex` from it before `rebuildDisplay()`, so the existing `rebuildDmenuDisplay` clamp bounds any out-of-range value for free.
- New `test/shell.d/menu-select-test.sh` drives the real script against a handshake-satisfying `omarchy-shell` stub (captures the `$4` payload, writes the pick to `selectionFile`, creates `doneFile`) covering: field present, field absent, missing value, stdin-fed options intact, sibling-flag coexistence, non-numeric coercion, and the no-existing-caller sweep.
- `docs/menu.md` "Select and input modes" now documents the `--width`/`--maxheight`/`--default-index` menu-args surface and the initial-only semantics (D-06).

## Task Commits

The plan mandates one atomic commit for the whole flag→payload→cursor path (CONTEXT specifics: the milestone's only cross-component contract change must be independently revertible), so tasks 1–3 executed and verified sequentially and landed together:

1. **Tasks 1–3: `--default-index` flag + payload field + `dmenuDefaultIndex` helper + `openDmenu` wiring + tests + docs** - `46956936` (feat, 6 files)

**Plan metadata:** pending — committed after this file via `gsd_run query commit`

## Files Created/Modified

- `bin/omarchy-menu-select` — `menu_defaultindex` variable, `--default-index` case arm, `$payload->{defaultIndex} = int($ARGV[6]) if length(...)` + argv append, header-comment line
- `shell/plugins/menu/MenuModel.js` — `dmenuDefaultIndex(payload, optionCount)` helper + guarded export
- `shell/plugins/menu/Menu.qml` — `property int dmenuDefaultIndex: 0`, `openDmenu` resolves and assigns it before `rebuildDisplay()`, D-05 initial-only comment in `setFilter`
- `test/shell.d/menu-select-test.sh` — new end-to-end payload test via stub `omarchy-shell`
- `test/shell.d/menu-test.sh` — 11 node unit cases for the helper + 5 source pins on `openDmenu`/`setFilter`
- `docs/menu.md` — post-`--` menu-args documentation incl. `--default-index N` → `defaultIndex` field

## Decisions Made

- Followed locked decisions D-01..D-07 verbatim; naming (`dmenuDefaultIndex` for both the helper and the QML property) matches the `dmenuWidth`/`dmenuMaxHeight` shape per PATTERNS §2b.
- Commit granularity: single atomic commit per the plan's explicit instruction (task 3 action 3 + must_haves prohibition), not per-task commits — the plan's acceptance criteria require `git show --stat HEAD` to list exactly the six files.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. All plan line references matched the working tree exactly.

## Verification Results

- `bash test/shell.d/menu-select-test.sh` — 10/10 `ok` assertions, exit 0
- `bash test/shell.d/menu-test.sh` — all assertions pass including 11 new helper cases + 5 new source pins, exit 0
- `bash -n bin/omarchy-menu-select` — clean
- `node -e` helper check — `dmenuDefaultIndex({defaultIndex:1},3) === 1`
- `./test/cli` — exit 0 (metadata lint green; `# omarchy:args=` unchanged)
- `./test/shell` — 7 of 239 files failed, all pre-existing environmental (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths — reproducing at base per STATE.md); `menu-select-test.sh` ran and passed inside the suite

## User Setup Required

None - no external service configuration required.

## Pending UAT (running-UI verification — NOT executed)

The development shell loads the packaged `/usr/share/omarchy` tree rather than this working repo (Phase 2 precedent, STATE.md), so the visual half is recorded for the user, not executed. After `omarchy-restart-shell`:

1. `omarchy-menu-select "Pick" a b c -- --default-index 1` in a terminal → row `b` visibly highlighted; `wtype -k Return` → terminal prints `b`
2. `omarchy-menu-select "Pick" a b c -- --default-index 99` → last row highlighted, menu not wedged
3. Open with `-- --default-index 1`, type a filter char → highlight moves to row 0 (initial-only, D-05)
4. `omarchy-menu-timezone` renders and selects normally (stdin-fed regression spot-check)

## Next Phase Readiness

- The `--default-index` contract is green end-to-end; Phase 6's quality menu can consume `-- --default-index 1` to pre-highlight `medium` (cross-phase gate satisfied).
- No blockers. The flag is public surface documented in `docs/menu.md`; renaming later would touch docs and adopting callers (D-01 rated costly, locked).

---
*Phase: 04-menu-defaultindex-plumbing*
*Completed: 2026-09-15*

## Self-Check: PASSED
