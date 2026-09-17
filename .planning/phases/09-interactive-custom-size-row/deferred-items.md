# Phase 9 — Deferred Items

Informational findings from `09-REVIEW.md` (code review, 2026-09-17). None block completion.

| Ref | Item | Disposition |
|-----|------|-------------|
| IN-02 | Mint-guard `return 1` (main unwrap :640-641) vs `--target`'s `return 2` for the same `Invalid target size` class — unreachable by construction (the mint only produces `^[0-9]+$`), consistency note only | cosmetic; align if the block is touched again |
