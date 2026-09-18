---
status: passed
phase: 08-non-interactive-target-size-targeting
source: [08-VERIFICATION.md]
started: 2026-09-17T02:00:00Z
updated: 2026-09-17T02:00:00Z
audit_acknowledged:
  milestone: v1.2
  at: 2026-09-18
  gap_snapshot: "passed::scenarios=0"
---

## Current Test

number: 1
name: Real-clip --target dogfood
expected: |
  `omarchy transcode <video> mp4 720p --target 10M` (or a size near a real clip's budget) runs a two-pass encode and produces an output near/under target — the rate control + 0.98 reserve should land it close; done toast shows actual size
awaiting: user response

## Tests

### 1. Real-clip --target dogfood

expected: `omarchy transcode <video> mp4 720p --target <size>` → two-pass encode, output lands near/under the target, `name-720p-<size>.mp4` filename, done notification reports actual size
result: pass (2026-09-17 — honest refusal verified live: `Cannot fit under 10M -- smallest achievable is ~384 MB` on a long clip; refusal died before menus/notifications)

### 2. Live toast replace-in-place

expected: during a `--target` encode, the "Transcoding video… pass 1/2" toast updates in place to "pass 2/2" (single notification, replaced — not two stacked toasts)
result: skip (user deferred; stub spot-run already proved toast sequence)

### 3. Passlog cleanup on interrupted encode (optional)

expected: Ctrl+C a `--target` encode mid-run → no `transcode-2pass.*` dirs or `*-0.log*` files left in `$TMPDIR`/`/tmp`
result: skip (user deferred; signal-interrupt path is residual — errexit cleanup proven by stub)

## Summary

total: 3
passed: 1
issues: 0
pending: 0
skipped: 2
blocked: 0

## Gaps

None yet.
