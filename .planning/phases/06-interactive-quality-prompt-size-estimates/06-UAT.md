---
status: testing
phase: 06-interactive-quality-prompt-size-estimates
source: [06-VERIFICATION.md]
started: 2026-09-16T00:58:00+02:00
updated: 2026-09-16T00:58:00+02:00
---

## Current Test

number: 1
name: Quality menu render in the running UI
expected: |
  Cursor sits on `medium`; the three rows show `CRF N · ~N MB` subtexts un-elided at ~300px card width with uniform `detailRowHeight`; Enter picks medium
awaiting: user response

## Tests

### 1. Quality menu render in the running UI
expected: Open the quality menu in the running UI (`omarchy transcode <clip> mp4 1080p` after `omarchy-restart-shell`, or `wtype -k Return` to accept the default). Cursor sits on `medium`; the three rows show `CRF N · ~N MB` subtexts un-elided at ~300px card width with uniform `detailRowHeight`; Enter picks medium.
result: [pending]

### 2. Estimate-vs-actual dogfood
expected: Transcode 2–3 varied real clips through the quality menu and compare the shown `~N MB` against the real output size. Each estimate lands within ~2× of the actual output (CRF variance is expected — the check is that estimates land inside it, not that they are exact).
result: [pending]

### 3. Nautilus multi-select
expected: Select 2+ videos in Files → Transcode → complete the flow. The quality prompt appears once per file (locked behavior — verify understood, not broken).
result: [pending]

### 4. Partial positionals chain
expected: `omarchy transcode <clip> mp4` — the resolution prompt fires, then the quality prompt fires (D-00i two-prompt chain).
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
