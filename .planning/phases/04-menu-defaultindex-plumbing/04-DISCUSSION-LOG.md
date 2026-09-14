# Phase 4: Menu `defaultIndex` plumbing - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-15
**Phase:** 4-menu-defaultindex-plumbing
**Areas discussed:** None — user elected to skip discussion

---

## Gray Areas Offered

| Area | Options presented | Selected |
|------|-------------------|----------|
| Flag naming & API | `--default-index` vs `--initial-index` vs label-based | — |
| Filter semantics | Initial-only vs re-apply on filter clear | — |
| Docs & testability | docs/menu.md documentation; MenuModel.js vs inline resolution | — |

**User's choice:** "if everything is clear, we can move on to /gsd-plan" — all decisions were already locked by milestone research (`.planning/research/ARCHITECTURE.md`, `PITFALLS.md`), so the discussion step was skipped and CONTEXT.md was written directly from the locked decisions.

**Notes:** The research had verified insertion points (`Menu.qml:874` in `openDmenu`), the post-`--` arg constraint (16 existing callers), existing clamp safety, and the initial-only filter semantics. Remaining options were low-stakes and covered by recommendations.

## Agent's Discretion

- Internal QML/JS helper naming, test-file organization, commit granularity within the phase.

## Deferred Ideas

- Label-based default selection and `--print-label`-style helpers — not needed by any current caller.
- Re-applying the default after filter clear — rejected; initial-only is correct.
