---
phase: 05-non-interactive-quality-in-omarchy-transcode
reviewed: 2026-09-15T15:09:05Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - bin/omarchy-transcode
  - test/shell.d/transcode-quality-test.sh
  - default/agents/skills/omarchy/capture.md
  - manual/12-screenshots-recording.md
findings:
  critical: 0
  warning: 2
  info: 6
  total: 8
status: resolved
---

# Phase 5: Code Review Report

**Reviewed:** 2026-09-15T15:09:05Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** resolved — WR-01 fixed (medium-on-picture rejection row added; 29/29 green), WR-02 deferred to `deferred-items.md` (pre-existing format/resolution validation asymmetry — the plan explicitly forbade silently changing it), all Info items recorded in `deferred-items.md`

## Summary

Reviewed commit `59e97b01` (diff plus surrounding context) against the locked contract. The implementation is faithful: the strict `high|medium|low` whitelist validates in `main()` before any notification (bin/omarchy-transcode:205-218), `medium`/omitted produces byte-identical argv to the pre-change literals (verified against the `%q`-built expected line in the test), `high`/`low` select the locked tiers (x264 18/28, x265 20/28, gif fps 15/5) and suffix the filename `stem-<res>-<quality>`, `output_path` dedupes `name-2`/`name-3` via `[[ -e || -L ]]` before the Transcoding notification with no `-y`/`-n`, and `quality` stays un-normalized (empty) in `main()` for Phase 6's `-z` prompt trigger.

Verified empirically with a stub harness: `medium` on a picture is correctly rejected (the `[[ -n $quality ]]` gate is non-empty, not non-`medium`), an invalid quality on a non-media file still reports an error + non-zero exit pre-notification (it reports `Unsupported file type` from `media_type`, which runs first — reasonable precedence), `(( n += 1 ))` never returns status-1-on-zero (result ≥3), and spaced filenames survive quoting end-to-end. All 28 test assertions pass; the suite is non-vacuous (literal argv pin + both-direction `cmp`). No callers (nautilus extension, keybindings, menu) pass a 4th positional, so the new strict validation has no regression surface. PR #6698 conflict surface is minimal: the only overlapping file is `bin/omarchy-transcode` and the test file was deliberately named `transcode-quality-test.sh` to avoid the add/add collision.

The findings are hardening items, not contract violations: a missing test row for `medium`-on-picture (locked behavior is implemented but not pinned), an orphaned-notification asymmetry left over for format/resolution validation, and minor robustness notes.

## Warnings

### WR-01: `medium` as the 4th positional on a picture is never exercised by the e2e

**File:** `test/shell.d/transcode-quality-test.sh:150`
**Issue:** The picture-rejection row passes `img.png jpg medium high` — only `high` is tested as the 4th positional. The locked contract requires `[[ -n $quality ]]` gating so that **any** non-empty 4th positional (including the valid tier `medium`) is rejected on pictures. The implementation at bin/omarchy-transcode:205-209 is correct today, but a regression to tier-aware gating (e.g. `[[ $quality != "medium" ]]` in the picture check, which would look plausible to a future editor since `medium` is "harmless" on videos) would silently pass this suite. The plan explicitly calls out the `[[ -n ]]`-not-`!= medium` gate as a contract point, so the missing row is a real coverage gap on a locked decision.
**Fix:** Add a parallel row after line 153:

```bash
if run_transcode "$TMPDIR/img.png" jpg medium medium; then
  fail "a picture transcode rejects an explicit medium 4th positional"
fi
pass "a picture transcode rejects an explicit medium 4th positional"
```

### WR-02: Orphaned "Transcoding video…" notification still fires for invalid format/resolution

**File:** `bin/omarchy-transcode:236-240`
**Issue:** This phase moved *quality* validation ahead of the start notification (the D-01 "no orphan notification" rule), but `format` and `resolution` are still validated inside `transcode_video` — which runs **after** `output_path` and the `omarchy-notification-send "Transcoding video…"` call. Verified empirically: `omarchy transcode in.mov avi 1080p` sends `Transcoding video… in.mov to avi (1080p)` and then exits 1 with `Invalid video format: avi`; same for a bogus resolution. This is pre-existing behavior for those two args (not a regression introduced by the diff), but the change creates a two-tier validation scheme where the phase's own invariant — fail before notification — applies to quality only, and a fully-specified non-interactive invocation can still emit a start notification for a run that fails instantly.
**Fix:** Validate non-empty `format`/`resolution` in `main()` before `output_path`, mirroring the quality block (e.g. a `case` on each when `[[ -n $format ]]`/`[[ -n $resolution ]]`), keeping the in-function `case` arms as defense for the interactive-menu path.

## Info

### IN-01: Positionals beyond the 4th are silently dropped

**File:** `bin/omarchy-transcode:190-193`
**Issue:** `omarchy transcode in.mov mp4 1080p low extrajunk` exits 0 and silently ignores `extrajunk` (verified). Now that slot 4 is meaningful, silently swallowing slot 5+ can mask user error (e.g. a misplaced flag lands in `positional[4]` and is ignored entirely).
**Fix:** After `quality="${positional[3]:-}"`, add `(( ${#positional[@]} <= 4 )) || { echo "Too many arguments" >&2; return 2; }` — or leave as-is if silent tolerance is deliberate; pre-change behavior also ignored extras.

### IN-02: `*)` quality arm in `transcode_video` is unreachable from `main()`

**File:** `bin/omarchy-transcode:126-129`
**Issue:** `main()` validates quality at lines 211-217 before `transcode_video` is ever called, so the `*)` arm is dead code on the only call path. This is intentional defense-in-depth per the plan ("keep this arm — file idiom + sourced-function safety"), so no action required; noted for completeness.
**Fix:** None needed — keep as defensive depth, optionally comment that `main()` validates first.

### IN-03: TOCTOU window between dedupe check and encoder open

**File:** `bin/omarchy-transcode:65-70` (check) vs `:135-141` (ffmpeg write)
**Issue:** If a file materializes at `$candidate` between the `[[ -e || -L ]]` loop and ffmpeg's open, ffmpeg falls back to its stdin `[y/N]` prompt — on a detached/keybind launch that can hang or abort. This is the plan's explicitly accepted T-05-04 ("degrades to today's prompt/refuse behavior — never a silent clobber") and the contract forbids `-n`, so it cannot be closed within the locked design; recorded here so the acceptance is visible in the review trail.
**Fix:** None within the locked contract (no `-y`/`-n` allowed). If ever revisited, `-n` on ffmpeg is the clean close.

### IN-04: `file://` clipboard URI is not percent-encoded for spaced filenames

**File:** `bin/omarchy-transcode:154`
**Issue:** `uri="file://$(realpath -- "$output")"` embeds raw spaces/metachars into a `text/uri-list` payload — a `my clip-1080p.mp4` output yields `file:///tmp/my clip-1080p.mp4`, which strict URI consumers may reject. Pre-existing (unchanged by this commit) and outside the locked contract; the dedupe work makes spaced/metachar names slightly more likely to surface, so it is worth noting.
**Fix:** Percent-encode path bytes when building the URI (e.g. `realpath` output through a small encoder), or accept the liberal-parser reality; not a Phase 5 blocker.

### IN-05: `notify_line`/`ffmpeg_line` extraction exits silently if grep finds nothing

**File:** `test/shell.d/transcode-quality-test.sh:142-143`
**Issue:** `notify_line=$(grep -n 'Transcoding' "$calls" | …)` runs under `set -euo pipefail`; if the notification line were absent, the assignment fails and the script exits 1 *before* reaching the descriptive `fail` at line 144 — the test still fails correctly, just without the helpful `cat "$calls"` detail. Minor diagnostics gap only.
**Fix:** Append `|| true` to each extraction and let the `(( notify_line < ffmpeg_line )) || fail` assertion report (empty operands make `(( ))` return non-zero → the `fail` path runs with the calls dump).

### IN-06: No-overwrite-flag pin could pass vacuously if `$ffmpeg_calls` is missing/empty

**File:** `test/shell.d/transcode-quality-test.sh:295`
**Issue:** `if grep -E '…-[yn]…' "$ffmpeg_calls"` on a nonexistent/empty file yields no match → the `if` body is skipped → `pass` is printed. In practice unreachable (a dozen earlier assertions require recorded ffmpeg lines and `run_transcode` appends them to `$ffmpeg_calls`), so the pin is effectively guarded; noting the theoretical vacuous-pass shape.
**Fix:** Optionally guard with `[[ -s $ffmpeg_calls ]] || fail "ffmpeg calls were recorded"` before the flag grep.

### IN-07: Notifications omit the selected quality tier

**File:** `bin/omarchy-transcode:239,242`
**Issue:** The start/success notifications say `in.mov to mp4 (1080p)` / `Transcoded to 1080p mp4` regardless of `high`/`low`, so a non-default-tier run is indistinguishable in the notification stream (the filename suffix carries the only evidence). Purely cosmetic.
**Fix:** If desired, append `($resolution, $quality)` when `[[ -n $quality && $quality != "medium" ]]` — same predicate as `output_path`.

---

_Reviewed: 2026-09-15T15:09:05Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_

## REVIEW COMPLETE

- Critical: 0
- Warning: 2
- Info: 6
- Total: 8
