---
status: testing
phase: 04-menu-defaultindex-plumbing
source: [04-VERIFICATION.md]
started: 2026-09-15T11:40:00Z
updated: 2026-09-15T11:40:00Z
---

## Current Test

number: 1
name: Pre-highlighted row is visibly selected and Enter picks it
expected: |
  `omarchy-menu-select "Pick" a b c -- --default-index 1` opens with row `b` highlighted; pressing Return prints `b`
awaiting: user response

## Tests

### 1. Pre-highlighted row is visibly selected and Enter picks it
expected: Run `omarchy-menu-select "Pick" a b c -- --default-index 1` in a terminal → row `b` visibly highlighted; `wtype -k Return` (or pressing Return) → terminal prints `b`
result: [pending]

### 2. Out-of-range index clamps to last row without wedging
expected: `omarchy-menu-select "Pick" a b c -- --default-index 99` → last row (`c`) highlighted, menu responds normally
result: [pending]

### 3. Typing a filter resets the highlight to row 0
expected: Open with `-- --default-index 1`, type a filter character → highlight moves to row 0 (initial-only semantics)
result: [pending]

### 4. Stdin-fed menu regression spot-check
expected: `omarchy-menu-timezone` renders and selects normally (no `defaultIndex` in its payload path)
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
