---
phase: "4"
slug: "menu-defaultindex-plumbing"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: validated
nyquist_compliant: true
wave_0_complete: true
created: "2026-09-15"
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test suites (`test/shell.d/*-test.sh` via `test/shell`) + node unit tests via `run_node_test` |
| **Config file** | none — existing `test/shell.d/base-test.sh` harness |
| **Quick run command** | `./test/shell` |
| **Full suite command** | `./test/all` (cli + shell) |
| **Estimated runtime** | ~30–60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./test/shell`
- **After every plan wave:** Run `./test/all`
- **Before `/gsd-verify-work`:** Full suite must be green (7 pre-existing environmental `test/shell` failures at base are not attributable to this phase — see RESEARCH §8)
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | MENU-01 | — | N/A | tracer e2e (stub omarchy-shell) | `./test/shell` (menu-select-test.sh) | ✅ | ✅ green (10/10) |
| 04-01-02 | 01 | 1 | MENU-01 | — | N/A | unit + source pins | `./test/shell` (menu-test.sh node tests, menu-select-test.sh) | ✅ | ✅ green (16 assertions) |
| 04-01-03 | 01 | 1 | MENU-01 | — | N/A | manual (running UI) | `omarchy-menu-select "Pick" a b c -- --default-index 1` + `wtype -k Return` | — | ⬜ pending UAT |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Task IDs are indicative — the planner may re-split; keep this map in sync with the shipped PLAN.md.*

---

## Wave 0 Requirements

- [x] `test/shell.d/menu-select-test.sh` — new end-to-end test: stub `omarchy-shell` satisfying the `selectionFile`/`doneFile` handshake, asserting `defaultIndex` payload presence/absence, `--default-index` missing-value error, stdin-fed path, and sibling-flag coexistence (see RESEARCH §7 Layer B for the stub sketch)

*Existing `menu-test.sh` + `base-test.sh` infrastructure covers the node-layer and source-pin assertions.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Row `b` visibly pre-highlighted; Enter selects it | MENU-01 | Visual state requires the running shell (per `agents/skills/visual-verification.md`; needs `omarchy-restart-shell`) | `omarchy-menu-select "Pick" a b c -- --default-index 1` → `b` highlighted; `wtype -k Return` prints `b` |
| Out-of-range clamps to last row | MENU-01 | Visual | `-- --default-index 99` → last row highlighted, menu not wedged |
| Typing resets highlight to row 0 | MENU-01 | Visual interaction | Open with `--default-index 1`, type a filter char → highlight at row 0 |
| Stdin-fed menu unaffected | MENU-01 | Regression spot-check | `omarchy-menu-timezone` renders and selects normally |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated 2026-09-15 (audit below)

---

## Validation Audit 2026-09-15

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

All three tasks verified post-execution: 04-01-01 e2e (10/10 `ok` in `menu-select-test.sh`), 04-01-02 unit + source pins (16 assertions in `menu-test.sh`), 04-01-03 manual-only running-UI checklist (pending `/gsd-verify-work`, recorded in `04-01-SUMMARY.md` Pending UAT). `./test/all` clean modulo the 7 pre-existing environmental failures at base.
