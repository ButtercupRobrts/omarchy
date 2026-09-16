---
phase: 07-completion-size-notification-docs
reviewed: 2026-09-16T16:30:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - bin/omarchy-transcode
  - test/shell.d/transcode-quality-test.sh
  - manual/12-screenshots-recording.md
findings:
  critical: 0
  warning: 1
  info: 6
  total: 7
status: issues_found
resolution: "WR-01 fixed in 972a1bba (sub-1 MiB outputs report <1 MB, never 0 MB, + pinned test row); IN-04 stale comment corrected in the same commit; remaining INFO items are advisory"
---

# Phase 7: Code Review Report

**Reviewed:** 2026-09-16
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found (WR-01 since fixed in `972a1bba`)
**Commits:** `4e0e1f89` test(07), `22c28a7d` feat(07-01), `8d52171b` fix(07) — order and subjects confirmed via `.git/logs/HEAD`; per-commit `--stat` boundaries not diff-verified (static review).

## Summary

Reviewed `output_size_label()` (bin/omarchy-transcode:289-294), the `size` local and both done-notification arms (:298, :384-385, :389-390), the `estimate_label` `%.0f` fix (:238), the `FAKE_OUT_BYTES`/`FAKE_ENCODE_RC` stub knobs + IN-06 guard + 7 new assertion rows in the harness, and the `manual/12` :70/:72 prose — against the plan's must_haves and research §Security Domain.

High-level assessment: the change is correct and well-pinned. The stat→regex-gate→awk chain matches the Phase-6 probe idiom exactly — `|| true` inside the command substitution so `set -e`/`pipefail` can't abort, `^[0-9]+$` gate before `awk -v` so C-escape interpretation is unreachable, `local` split from the substitution so statuses aren't masked. `${size:+ ($size)}` is the colon form, so an empty/unset label expands to nothing — degrade is one expansion, no `if` tree, and the helper can't emit a partial label (awk is its last statement). Both PUA glyphs verified byte-intact (U+F03D on :381/:385, U+F03E on :390). The `awk -v` injection surface is sealed by the digit gate; the notification body is a typed `s` parameter in the busctl `susssasa{sv}i` call (bin/omarchy-notification-send:196-199), and the label is digits + literal ` MB` by construction.

The stub knobs behave as designed: `${!#}` correctly resolves the last positional for both `ffmpeg … "$output"` and `magick … "$output"` argv shapes, `truncate` runs before `exit "${FAKE_ENCODE_RC:-0}"` (a combined-knob run would leave a sized partial file — matching real-encoder partial-output semantics; no current row combines them), and per-invocation env prefixes don't leak between rows. The IN-06 fix is right: `|| true` inside `$(…)` converts the empty-grep abort into a descriptive `fail`, and the `[[ -n && -n ]]` guard sits before the `(( ))` compare. The new rows genuinely distinguish — the dedupe row's 0-byte collision fixture renders `(0 MB)` if the wrong path were stat'd, the degrade row anchors `clipboard\.$` and negative-checks ` MB)`, the WR-01 row's `~6`/`~4`/`~2` fails as `~5`/`~3`/`~1` under the old `%d`. Fixture ownership (`rm -f` after asserting) is honored at :584, :591, :626, :639. 51 `pass` calls counted, matching the SUMMARY.

The one substantive finding: `output_size_label` rendered `0 MB` for a real non-empty output under ~0.5 MiB, where the sibling `estimate_label` deliberately floors at `~1 MB` (WR-01 below). **Resolved in `972a1bba`:** the helper now emits `<1 MB` for `0 < b < 1 MiB` (true 0-byte outputs still report `0 MB`), with a `FAKE_OUT_BYTES=200000` pin.

## Warnings

### WR-01: `output_size_label` reports `0 MB` for non-empty outputs under ~0.5 MiB — FIXED in `972a1bba`

**File:** `bin/omarchy-transcode:293`
**Issue:** `awk 'BEGIN { printf "%.0f MB", b / 1048576 }'` rounds `0 < b < 524288` down to `0`, so a real output file — e.g. a `jpg low` of an already-small image, or a tiny gif — produces `Saved and copied to clipboard (0 MB).` A notification claiming zero size for a non-empty file reads as a lie in exactly the display string this phase exists to ship. The sibling `estimate_label` already handles this band (`mb < 1 → "~1 MB"`, :234), so the estimate and the actual could disagree in kind: the menu can say `~1 MB` and the done toast `0 MB` — and `manual/12:72` now explicitly invites the user to "check it against the estimate." Reachable in normal use (picture transcodes of small inputs), not just a corner case.
**Fix applied:** `0 < b < 1048576` now prints `<1 MB`; `b == 0` still prints `0 MB`. New test row pins `FAKE_OUT_BYTES=200000` → `(<1 MB)`.

## Info

### IN-01: `truncate` runs before the `FAKE_ENCODE_RC` exit — combined knobs leave a sized partial file

**File:** `test/shell.d/transcode-quality-test.sh:43-46`
**Issue:** `truncate -s` executes before `exit "${FAKE_ENCODE_RC:-0}"`, so a row setting both knobs would create a real sized file *and* fail the encode. Defensible — it models a real encoder leaving a partial output, and the script still aborts before the done notification — and no current row combines them. Flagging only because a future row that does must `rm -f` the partial file or it poisons later dedupe rows.

### IN-02: Notification count and start-notification body are not pinned

**File:** `test/shell.d/transcode-quality-test.sh` (new rows :574-640)
**Issue:** The plan's must_haves claim "notification count is unchanged" and "the start notification is byte-unchanged," but no row counts `notification:` lines or pins the start body verbatim. A regression emitting a third notification, or mutating the `in.mov to mp4 (1080p)` body, passes all rows. One `grep -c '^notification:'` assertion on an existing happy-path row would close it cheaply.

### IN-03: Comment at :191 slightly stale under the new knob semantics

**File:** `test/shell.d/transcode-quality-test.sh:190-191`
**Issue:** "the stubs never create it, so the fixture is the only file" — the absolute phrasing predates `FAKE_OUT_BYTES`; contextually true for this row only because the knob is unset. Nit: "without FAKE_OUT_BYTES the stub creates nothing" would match the new model.

### IN-04: WR-01 row comment double-counts the audio term — FIXED in `972a1bba`

**File:** `test/shell.d/transcode-quality-test.sh:643`
**Issue:** "18 s at 720p is 5.8/3.6/1.9 MiB + 192k audio" — the figures already include the 192k term (18 s × (2500+192) kbps × 125 / 1048576 = 5.78). **Fix applied:** comment now reads "with 192k audio is 5.8/3.6/1.9 MiB".

### IN-05: `manual/12:72` invites an estimate check pictures never got

**File:** `manual/12-screenshots-recording.md:72`
**Issue:** "the notification tells you the actual size of the file it wrote, so you can check it against the estimate" — the paragraph covers pictures and videos, but only video transcodes show a quality-step estimate; a picture user sees a size with nothing to check it against. Prose looseness, not an inaccuracy about the mechanism itself.

### IN-06: Ordering-check comment overclaims what the assertion observes

**File:** `test/shell.d/transcode-quality-test.sh:199-207`
**Issue:** The comment says "the deduped path must be resolved — and the encode started — only after the 'Transcoding' notification," but the assertion only observes notification-line < ffmpeg-line in the stub log; `output_path` resolution order isn't observable there. Pre-existing phrasing (the guard fix is what changed); also note `ffmpeg_line` now greps `'^ffmpeg '` anchored — a small improvement over the plan's unanchored form, worth keeping.

---

_Reviewed: 2026-09-16_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
