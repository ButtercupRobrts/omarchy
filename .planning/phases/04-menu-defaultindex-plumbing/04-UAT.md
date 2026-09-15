---
status: complete
phase: 04-menu-defaultindex-plumbing
source: [04-VERIFICATION.md]
started: 2026-09-15T11:40:00Z
updated: 2026-09-15T12:05:00Z
---

## Current Test

number: 4
name: Stdin-fed menu regression spot-check
expected: |
  `omarchy-menu-timezone` renders and selects normally (no `defaultIndex` in its payload path)
awaiting: none — all tests passed

## Tests

### 1. Pre-highlighted row is visibly selected and Enter picks it
expected: Run `omarchy-menu-select "Pick" a b c -- --default-index 1` in a terminal → row `b` visibly highlighted; `wtype -k Return` (or pressing Return) → terminal prints `b`
result: pass

### 2. Out-of-range index clamps to last row without wedging
expected: `omarchy-menu-select "Pick" a b c -- --default-index 99` → last row (`c`) highlighted, menu responds normally
result: pass

### 3. Typing a filter resets the highlight to row 0
expected: Open with `-- --default-index 1`, type a filter character → highlight moves to row 0 (initial-only semantics)
result: pass

### 4. Stdin-fed menu regression spot-check
expected: `omarchy-menu-timezone` renders and selects normally (no `defaultIndex` in its payload path)
result: pass

## Summary

total: 4
passed: 4
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
