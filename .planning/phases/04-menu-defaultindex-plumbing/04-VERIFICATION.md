---
phase: 04-menu-defaultindex-plumbing
verified: 2026-09-15T11:30:21Z
status: human_needed
score: 7/7 must-haves verified
covered_files:
  - .planning/REQUIREMENTS.md
  - .planning/phases/04-menu-defaultindex-plumbing/04-01-PLAN.md
  - .planning/phases/04-menu-defaultindex-plumbing/04-01-SUMMARY.md
  - bin/omarchy-menu-select
  - docs/menu.md
  - shell/plugins/menu/Menu.qml
  - shell/plugins/menu/MenuModel.js
  - test/shell.d/menu-select-test.sh
  - test/shell.d/menu-test.sh
covered_digest: "v1:sha256:5c76a519425ee97c925a27c00b0b746794274a3a8a87da8d9d8157a0dfbb402f"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "After `omarchy-restart-shell`, run `omarchy-menu-select \"Pick\" a b c -- --default-index 1` in a terminal, then press Enter (or `wtype -k Return`)"
    expected: "Row `b` is visibly highlighted on open; Enter prints `b` to the terminal"
    why_human: "The dev shell loads the packaged /usr/share/omarchy tree, not this working repo — visual pre-highlight and Enter-selects require the running shell"
  - test: "Run `omarchy-menu-select \"Pick\" a b c -- --default-index 99`"
    expected: "Last row (`c`) is highlighted; the menu is not wedged"
    why_human: "Out-of-range visual clamp is confirmed by the rebuildDmenuDisplay bounds check in code, but the rendered result needs the running shell"
  - test: "Open with `-- --default-index 1`, then type a filter character"
    expected: "The highlight moves to row 0 (initial-only semantics, D-05)"
    why_human: "Filter interaction is a runtime state transition in the running shell"
  - test: "Run `omarchy-menu-timezone` and select a zone normally"
    expected: "Stdin-fed menu renders and selects exactly as before (regression spot-check)"
    why_human: "End-to-end stdin-fed caller path requires the running shell"
---

# Phase 4: Menu `defaultIndex` plumbing Verification Report

**Phase Goal:** `omarchy-menu-select` accepts `--default-index N` after `--`, emits `defaultIndex` in the select-mode JSON payload, and `Menu.qml`'s `openDmenu` initializes `selectedIndex` from it — with every existing caller byte-identical in behavior
**Verified:** 2026-09-15T11:30:21Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1 | `omarchy-menu-select Pick a b c -- --default-index 1` emits `"defaultIndex":1` in the select-mode JSON payload and returns the selection through the tempfile handshake unchanged | ✓ VERIFIED | e2e `menu-select-test.sh` ran green: "emits the default index in the payload" + "returns the picked row". Independently reproduced: real perl payload block emits `"defaultIndex":1` for flag value `1` |
| 2 | With no flag, the payload carries no `defaultIndex` key at all — all verified call sites, `omarchy-menu-file`'s `"$@"` pass-through, and the routed `omarchy menu select` path are byte-identical | ✓ VERIFIED | e2e "omits the default index when the flag was not passed" green; direct perl run with empty `$ARGV[6]` emits zero `defaultIndex` occurrences. `grep -rln -- '--default-index' bin/` outside `omarchy-menu-select` is empty. `omarchy-menu-file:48` invokes `omarchy-menu-select "$label" -- --width 800 --maxheight 500 "$@"` (no flag); `bin/omarchy:1047` execs the resolved binary with args unchanged |
| 3 | `openDmenu` assigns `selectedIndex` from `MenuModel.dmenuDefaultIndex(payload, dmenuOptions.length)` before `rebuildDisplay()` runs, so Enter activates the pre-highlighted row | ✓ VERIFIED | `Menu.qml:874` resolves via helper (after `dmenuOptions` at :868), `:878` `selectedIndex = dmenuDefaultIndex`, `:882` `rebuildDisplay()` — ordering pinned by a green source-pin test (`indexOf` ordering assertion that fails on regression). Enter path statically traced: `cursorActive = mode !== "input"` (:879) → `Key_Return` → `activateIndex(selectedIndex)` (:1161). Visual confirmation listed under human verification |
| 4 | Out-of-range, negative, non-integer, and non-numeric `defaultIndex` values resolve inside `[0, count-1]` and never wedge the menu | ✓ VERIFIED | `MenuModel.js:497-503` floor/NaN/negative/clamp guards; 11 node cases green in `menu-test.sh` (independently re-run: all pass, incl. `Infinity`→`count-1`). Non-finite e2e (`1e1000`) runs under `timeout 10` and emits `"defaultIndex":0` — no bare `Inf`/`NaN` token reaches the JSON (WR-01 fix confirmed live) |
| 5 | Typing in the filter still resets the highlight to row 0 — initial-only semantics, documented by a comment (D-05) | ✓ VERIFIED | `Menu.qml:723-724` D-05 comment, `:725` `root.selectedIndex = 0` unconditional inside `setFilter`; printable-char key handler calls `setFilter` (:1165-1166). Source pin asserts the reset survives in the `setFilter` body — green. Runtime typing confirmation listed under human verification |
| 6 | `--default-index` with no following value exits 1 with `requires a value` on stderr; stdin-fed callers keep their option stream intact | ✓ VERIFIED | `bin/omarchy-menu-select:56-58` guard fires before any summon; e2e "rejects --default-index without a value" + "says --default-index requires a value" green. Stdin path: `mapfile` fallback at :72-74 runs only on empty argv options; e2e "keeps the stdin option stream intact behind the flag" green (`"options":["a","b"]` + `"defaultIndex":1`) |
| 7 | `docs/menu.md` documents the flag (D-06) | ✓ VERIFIED | `docs/menu.md:168-173` documents `--default-index N` → integer `defaultIndex` field, initial-only semantics, and absent-field row-0 default — accurate against the implementation |

**Score:** 7/7 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `bin/omarchy-menu-select` | `--default-index` post-`--` flag arm + `defaultIndex` payload field | ✓ VERIFIED | `menu_defaultindex` decl :30, case arm :54-61 (value-required guard, no `*)` arm), perl emission :97-100, argv append :102, header comment :15. `bash -n` clean |
| `shell/plugins/menu/MenuModel.js` | node-testable index resolution, exports `dmenuDefaultIndex` | ✓ VERIFIED | `dmenuDefaultIndex(payload, optionCount)` :497-503 in ES5 style with doc comment :493-496; exported under the `typeof module` guard :535 |
| `shell/plugins/menu/Menu.qml` | `openDmenu` initializes `selectedIndex` from resolved default before `rebuildDisplay()` | ✓ VERIFIED | `property int dmenuDefaultIndex: 0` :63; `MenuModel.dmenuDefaultIndex` call :874; `selectedIndex = dmenuDefaultIndex` :878; `rebuildDisplay()` :882. `MenuModel` imported :7 |
| `test/shell.d/menu-select-test.sh` | end-to-end payload test via stub `omarchy-shell` | ✓ VERIFIED | Stub captures `$4` payload and satisfies selectionFile/doneFile handshake (:20-31); 11 `ok` assertions, exit 0 |
| `test/shell.d/menu-test.sh` | node unit cases + Menu.qml source pins | ✓ VERIFIED | 11 `dmenuDefaultIndex` cases :644-654 + 5 openDmenu/setFilter pins :656-679; suite green |
| `docs/menu.md` | public flag/payload-field documentation | ✓ VERIFIED | "Select and input modes" section :168-173 |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `bin/omarchy-menu-select` | select-mode JSON payload | `defaultIndex` emitted iff `length($ARGV[6])` (:97-100) | ✓ WIRED | Reproduced live: flag→`"defaultIndex":1`; absent→no key; `1e1000`→`0` (regex-gated `int()` coercion) |
| `Menu.qml openDmenu` | `MenuModel.js` | `dmenuDefaultIndex = MenuModel.dmenuDefaultIndex(payload, dmenuOptions.length)` then `selectedIndex = dmenuDefaultIndex` before `rebuildDisplay()` | ✓ WIRED | :874/:878/:882; helper resolves and the existing `rebuildDmenuDisplay` clamp (:597-599) bounds the result |
| `test/shell.d/menu-select-test.sh` | `bin/omarchy-menu-select` | stub `omarchy-shell` captures `$4` payload + satisfies tempfile handshake | ✓ WIRED | `CAPTURED_PAYLOADS` file + `FAKE_PICK` pick written to `selectionFile`; test ran green end-to-end |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `bin/omarchy-menu-select` | `menu_defaultindex` → `$ARGV[6]` → `payload.defaultIndex` | caller argv after `--` | Yes — emitted only when the caller passed the flag | ✓ FLOWING |
| `Menu.qml` | `payload.defaultIndex` → `dmenuDefaultIndex` → `selectedIndex` → `activateIndex`/`revealCursor` | summon payload JSON | Yes — real caller data drives the highlight and Enter selection | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full e2e suite | `bash test/shell.d/menu-select-test.sh` | 11/11 `ok`, exit 0 | ✓ PASS |
| Node units + source pins | `bash test/shell.d/menu-test.sh` | all assertions green, exit 0 | ✓ PASS |
| Helper contract | `node -e` direct `dmenuDefaultIndex` cases (12 cases incl. NaN/null/Infinity/empty count) | all pass | ✓ PASS |
| Payload emission | real perl payload block: flag=`1` / absent / `1e1000` | `"defaultIndex":1` / no key / `"defaultIndex":0` | ✓ PASS |
| Syntax | `bash -n bin/omarchy-menu-select` | exit 0 | ✓ PASS |
| Caller sweep | `grep -rln -- '--default-index' bin/` outside the script | empty | ✓ PASS |

### Probe Execution

No probes declared or discovered for this phase — N/A.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| MENU-01 | 04-01 | `omarchy-menu-select` supports a pre-highlighted default row (`--default-index N` after `--`, carried through the JSON payload to `openDmenu`); all existing callers behave unchanged | ✓ SATISFIED | Truths 1-6 + artifacts; e2e + node coverage green. REQUIREMENTS.md:56 maps MENU-01→Phase 4 |

No orphaned requirements: REQUIREMENTS.md maps only MENU-01 to Phase 4, and it is declared in the plan.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | — | — | None. No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER markers in any of the six phase files; no stub patterns. Implementation commit `46956936` is atomic (exactly the six `files_modified` paths); WR-01 fixed in `634aea54` (verified live: `1e1000` → `"defaultIndex":0`, no hang); latent `--width`/`--maxheight` sibling defect correctly deferred to `deferred-items.md` (pre-existing, out of scope) |

### Human Verification Required

The dev shell loads the packaged `/usr/share/omarchy` tree, not this working repo — the running-UI half cannot be verified programmatically. After `omarchy-restart-shell`:

### 1. Visual pre-highlight and Enter-selects

**Test:** `omarchy-menu-select "Pick" a b c -- --default-index 1` in a terminal; press Enter (or `wtype -k Return`)
**Expected:** Row `b` visibly highlighted on open; Enter prints `b`
**Why human:** Rendered highlight and key activation require the running shell

### 2. Out-of-range clamp

**Test:** `omarchy-menu-select "Pick" a b c -- --default-index 99`
**Expected:** Last row (`c`) highlighted; menu not wedged
**Why human:** Visual confirmation of the `rebuildDmenuDisplay` clamp

### 3. Filter reset (initial-only semantics)

**Test:** Open with `-- --default-index 1`, type a filter character
**Expected:** Highlight moves to row 0
**Why human:** Runtime filter-interaction state transition

### 4. Stdin-fed regression spot-check

**Test:** `omarchy-menu-timezone` — render and select a zone normally
**Expected:** Unchanged behavior for a stdin-fed caller
**Why human:** End-to-end running-UI regression check

### Gaps Summary

No gaps. All code-level must-haves verified against the working tree with independently re-run tests; the only unverifiable surface is the running shell, covered by the human verification items above.

---

_Verified: 2026-09-15T11:30:21Z_
_Verifier: the agent (gsd-verifier)_
