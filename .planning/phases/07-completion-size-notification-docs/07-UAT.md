---
phase: 07-completion-size-notification-docs
status: pending
total: 3
passed: 0
issues: 0
pending: 3
---

# Phase 7 — User Acceptance Testing

All automated verification passed (10/10 must-haves, 52/52 focused assertions, cli green, shell green modulo the 7 documented environmental failures). The items below require the running UI / real encodes and cannot be checked from the harness.

## Test 1: Completion toast shows the real size (running UI)

Transcode any real video through the Files → Transcode flow (or `omarchy transcode <clip> mp4 1080p medium`). When it finishes, the done toast should read `Transcoded to 1080p mp4` / `Saved and copied to clipboard (N MB).` — legible, glyph intact, no truncation.

**Pass when:** the notification body carries the actual size in `(N MB)` (or `(<1 MB)` for tiny outputs).

## Test 2: Estimate → actual calibration (dogfood)

On a real clip, note the `~N MB` shown on the medium row of the quality menu, then compare with the `(N MB)` in the completion toast. They should be the same scale and within ~2× — the estimate is deliberately approximate; the pair is the calibration loop this milestone exists for.

**Pass when:** the actual size lands in the estimate's ballpark (within ~2×), confirming the estimate was honest.

## Test 3: Manual prose reads naturally

Read the updated "Transcoding before you share" section in `manual/12-screenshots-recording.md` (:68-74) as an end user would: it should now mention the video quality step, the rough per-choice estimate, and the actual size in the completion notification — in plain language, no CRF/codec jargon.

**Pass when:** the paragraph is accurate and reads naturally. (Note: the "check it against the estimate" phrasing at :72 applies to videos — pictures get a size but never saw an estimate; if that reads oddly to you, say so and it can be tightened.)

---

*Record results: mark each test pass/fail; any fail gets diagnosed into a fix plan via `/gsd-plan-phase 7 --gaps`.*
