---
status: testing
phase: 09-interactive-custom-size-row
source: [09-VERIFICATION.md]
started: 2026-09-17T03:00:00Z
updated: 2026-09-17T03:00:00Z
---

## Current Test

number: 1
name: Custom-row dogfood in the running menu
expected: |
  `omarchy transcode <video> mp4 1080p` → the quality menu shows `Custom size…` as the 4th/last row with a subtext, at the same height as the tier rows, `medium` still pre-highlighted → picking it opens the input card `Target size (e.g. 25M)` → typing `25M` and Enter starts a two-pass encode producing `name-1080p-25M.mp4`
awaiting: user response

## Tests

### 1. Custom-row dogfood
expected: `omarchy transcode <clip> mp4 1080p` → `Custom size…` renders 4th/last with subtext, medium pre-highlighted → input card → `25M` → two-pass run, `name-1080p-25M.mp4`, done toast with actual size
result: [pending]

### 2. Cancel / re-prompt UX
expected: Esc at the input prompt cancels silently (no encode, no toast); empty Enter and garbage input each re-prompt once with the `Invalid size — e.g. 25M` hint
result: [pending]

### 3. Optional spot-checks
expected: gif menu shows no Custom row; a below-floor answer refuses naming `~N MB` minimum
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps

None yet.
