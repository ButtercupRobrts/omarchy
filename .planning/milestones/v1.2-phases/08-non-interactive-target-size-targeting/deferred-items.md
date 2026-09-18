# Phase 8 — Deferred Items

Informational findings from `08-REVIEW.md` (code review, 2026-09-17). None block completion; each is recorded for future passes.

## Items

- **IN-01** — `--target ""` rejection is contract-locked but unpinned — add `""` to the reject loop inputs. Closed in Phase 9: `""` is in the reject loop (`for bad in abc -5M 0 25.5.2M ""`), 93/93 green.
  status: resolved
- **IN-02** — Trap comment describes a `-d` guard; shipped trap is path-baked `rm -rf` (correct by necessity — locals unbound at trap fire) — comment should say the explicit `rm -rf` makes the trap inert. Cosmetic; fix in next touch of that block.
  status: acknowledged
- **IN-03** — `plan_target` floor `case` lacked a `*)` arm. Closed in Phase 8 implementation: the step-down case's `*)` arm refuses naming the achievable minimum.
  status: resolved
- **IN-04** — Stub pass-2 arm records `out=` before the passlog check — looser fidelity than real ffmpeg; no false-green today. Test-harness refinement; optional.
  status: acknowledged
- **IN-05** — `--target` + positional-menu gif with unset resolution wastes a resolution prompt before refusing (locked check site, optional early check not taken). Pre-existing ordering convention; revisit only if menu flow changes.
  status: acknowledged
- **IN-06** — Retry `mv -f` TOCTOU is slightly worse than the accepted v1.1 class (`mv` never prompts). Accepted-risk class; inherent to check-then-move.
  status: acknowledged
