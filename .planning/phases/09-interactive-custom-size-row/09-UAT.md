---
status: passed
phase: 09-interactive-custom-size-row
source: [09-VERIFICATION.md]
started: 2026-09-17T03:00:00Z
updated: 2026-09-17T03:00:00Z
---

## Current Test

number: —
name: —
expected: —
awaiting: —

## Tests

### 1. Custom-row dogfood
expected: `omarchy transcode <clip> mp4 1080p` → `Custom size…` renders 4th/last with subtext, medium pre-highlighted → input card → `25M` → two-pass run, `name-1080p-25M.mp4`, done toast with actual size
result: [passed] — user ran `omarchy transcode "2009 - AMSTERDAM.m4v" mp4 1080p`, picked `Custom size…`, entered `400M`; two-pass encode produced the `-400M` output at/under 400 decimal MB in Files. Dogfood surfaced the IEC/SI unit mismatch, fixed in `4d422ffe` (all user-facing sizes now decimal).

### 2. Cancel / re-prompt UX
expected: Esc at the input prompt cancels silently (no encode, no toast); empty Enter and garbage input each re-prompt once with the `Invalid size — e.g. 25M` hint
result: [skipped] — covered by stub e2e pins (empty submit → hinted re-prompt, garbage → hinted re-prompt, Esc/second failure → cancel with zero ffmpeg calls)

### 3. Optional spot-checks
expected: gif menu shows no Custom row; a below-floor answer refuses naming `~N MB` minimum
result: [skipped] — gif row absence and forged-sentinel rejection pinned in the stub suite; the below-floor refusal was verified live during Phase 8 UAT (`--target 10M` → "smallest achievable ~384 MB", now decimal)

## Summary

total: 3
passed: 1
issues: 0
pending: 0
skipped: 2
blocked: 0

## Gaps

None.
