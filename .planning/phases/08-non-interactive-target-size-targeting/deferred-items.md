# Phase 8 — Deferred Items

Informational findings from `08-REVIEW.md` (code review, 2026-09-17). None block completion; each is recorded for future passes.

| Ref | Item | Disposition |
|-----|------|-------------|
| IN-01 | `--target ""` rejection is contract-locked but unpinned — add `""` to the reject loop inputs | candidate for Phase 9 test pass (same parser is reused by `Custom size…`) |
| IN-02 | Trap comment (:392) describes a `-d` guard; shipped trap is path-baked `rm -rf` (correct by necessity — locals unbound at trap fire) — comment should say the explicit `rm -rf` makes the trap inert | cosmetic; fix in next touch of that block |
| IN-03 | `plan_target` floor `case` lacks a `*)` arm — unreachable today (resolution validated before the planner), but the helpers are shaped for Phase-9 reuse where an unvalidated caller could hit it | fix in Phase 9 when the interactive caller lands, or now if touched |
| IN-04 | Stub pass-2 arm records `out=` before the passlog check — looser fidelity than real ffmpeg; no false-green today | test-harness refinement; optional |
| IN-05 | `--target` + positional-menu gif with unset resolution wastes a resolution prompt before refusing (locked check site, optional early check not taken) | pre-existing ordering convention; revisit only if menu flow changes |
| IN-06 | Retry `mv -f` TOCTOU is slightly worse than the accepted v1.1 class (`mv` never prompts) | accepted-risk class; inherent to check-then-move |
