---
phase: 06-interactive-quality-prompt-size-estimates
reviewed: 2026-09-15T22:44:24Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - bin/omarchy-transcode
  - test/shell.d/transcode-quality-test.sh
  - test/shell.d/menu-select-test.sh
findings:
  critical: 0
  warning: 1
  info: 7
  total: 8
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-09-15T22:44:24Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Reviewed the six new helpers (`video_duration`, `video_audio_kbps`, `quality_token`, `quality_kbps`, `estimate_label`, `select_quality`, bin/omarchy-transcode:162–285), the `[[ $type == "video" && -z $quality ]]` prompt block in `main()` (:365–367), the `usage()` touch (:17), and the extended stub harnesses — against the diff `de7ce0b3^..HEAD` and in context of the whole script.

High-level assessment: the implementation is defensively correct in the hot spots. Every probe is `|| true`-/`if`-guarded and regex-gated before reaching `awk -v` under `set -euo pipefail`; `local` declarations are separated from command-substitution assignments so exit statuses are not masked; the menu pick is stripped at the first tab and re-validated `high|medium|low` inside `select_quality`, so a foreign label dies before the notification boundary (verified live: `$(touch /tmp/pwned)\tjunk` pick → `Invalid video quality`, no file created); Esc aborts silently with status 1 matching sibling prompts; all quoting is sound (`"${rows[@]}"`, quoted probe args); the CRF/fps/kbps tables match `transcode_video` and the locked D-00e table exactly (verified at 720p/1080p/4k). Both suites run green (`transcode-quality-test.sh` 44/44 — the SUMMARY says 43, see IN-07; `menu-select-test.sh` 11/11).

The one substantive finding is a small math/display slip in `estimate_label` that systematically floors sub-10 MiB estimates (WR-01). Everything else is INFO-level hygiene or pre-existing context.

## Warnings

### WR-01: `estimate_label` floor-truncates 2-sig-fig results below 10 MiB

**File:** `bin/omarchy-transcode:238`
**Issue:** The awk block computes `r` correctly rounded to 2 significant figures (`d = int(log(mb)/log(10)) - 1` yields `d = -1` for `mb ∈ [1,10)`, so `r` carries a tenth — e.g. `mb = 1.9` → `r = 1.9`), but `printf "~%d MB", r` then truncates the fraction. Verified live: `estimate_label 1 15938 0 ""` (1.90 MiB) prints `~1 MB` — a ~48% understatement; `9.94 MiB` prints `~9 MB`. Every other decade rounds at ±5%; this band floors by up to ~1 MB, which is not a rounding of the estimate at any sig-fig precision and deviates from the locked D-00h "1–2 sig figs" contract. The affected range is exactly where short-clip `720p/low` and `720p/medium` estimates land (60 s → `~6`/`~12` MB), so it is reachable in normal use, not just a corner case.

**Fix:**
```diff
-    printf "~%d MB", r
+    printf "~%.0f MB", r
```
`%.0f` rounds (`1.9` → `~2 MB`, `9.9` → `~10 MB`) and keeps the no-decimals rule. (A `~%g MB` alternative would print `~1.9 MB` and violate D-00h's no-decimals clause.)

## Info

### IN-01: Duration gate admits malformed numerics

**File:** `bin/omarchy-transcode:166`
**Issue:** `[[ $duration =~ ^[0-9.]+$ ]]` accepts strings real ffprobe never emits for `format=duration` but that aren't valid numbers — `1.2.3.4`, `.`, `1.`. Verified live: `1.2.3.4` passes the gate and awk numifies the leading prefix (`1.2`), yielding a silently wrong (if cosmetic) estimate. Downstream-safe — `awk -v` can't be escaped through `[0-9.]` — but the gate is looser than its own contract.
**Fix:** `[[ $duration =~ ^[0-9]+(\.[0-9]+)?$ ]]`

### IN-02: Deliberate CRF/fps table duplication is a latent drift hazard

**File:** `bin/omarchy-transcode:185-213` (mirrors `:122-130`)
**Issue:** `quality_token` re-hardcodes all nine `crf_x264`/`crf_x265`/`gif_fps` constants from `transcode_video`. The comment documents this as deliberate (shared table would refactor inside the PR #6698 conflict window), and the harness pins both sides (e.g. `-crf 23` argv vs `CRF 23` subtext at 1080p and 4k; `fps=15` vs `15 fps` for gif), so tests would catch drift today. Flagging only so the duplication is removed once #6698 settles — a future change that edits `transcode_video` without updating the pins could still desynchronize the two.

### IN-03: Dead clamp in `estimate_label`

**File:** `bin/omarchy-transcode:236`
**Issue:** `if (d < -1) d = -1` is unreachable: `mb < 1` early-returns two lines above, so `log10(mb) >= 0` and `d >= -1` always. Harmless dead code; remove or leave — the `mb < 1` floor already covers the intent.

### IN-04: ffprobe/stat invoked on un-terminated user-controlled path

**File:** `bin/omarchy-transcode:164-165, 174`
**Issue:** `ffprobe ... "$1"` passes the input path as the last argv element with no option terminator, so a leading-dash filename (`-v`, `-i`) is parsed as an option and the probe errors out — degrading to qualitative rows rather than misbehaving. The comment documents this as deliberate convention parity ("matches the repo's existing ffprobe call sites"), ffprobe/ffmpeg don't honor `--` anyway, and the identical exposure already exists at `ffmpeg -i "$input"` (:135-141), so this adds no new risk class. Noted for completeness; a `-i ./`-style path prefix would be the only real hardening and isn't the repo's convention.

### IN-05: `video_audio_kbps` runs even when the duration probe already failed

**File:** `bin/omarchy-transcode:256`
**Issue:** When `video_duration` fails (`duration=""`), the mp4 branch still spawns a second ffprobe for `video_audio_kbps`, whose result is then unused (all rows take the qualitative fallback). Cosmetic — one wasted subprocess on the degraded path; the conservative-192 semantics remain correct. A `[[ -n $duration ]] && audio_kbps=$(video_audio_kbps "$input")` guard would skip it.

### IN-06 (pre-existing): Notification-ordering assertion can false-pass

**File:** `test/shell.d/transcode-quality-test.sh:192-195`
**Issue:** `notify_line` is empty when no `Transcoding` line exists in `$calls`; `(( notify_line < ffmpeg_line ))` then evaluates the empty variable as 0, so `0 < ffmpeg_line` passes even if the notification never fired. A regression that dropped the notification while still running ffmpeg would not be caught by this row. Pre-existing Phase-5 block, unchanged by this diff — INFO only per review scope.
**Fix:** Guard the empty case first: `[[ -n $notify_line && -n $ffmpeg_line ]] || fail ...` before the arithmetic compare.

### IN-07 (test): Residual coverage gaps in the extended harness

**File:** `test/shell.d/transcode-quality-test.sh`
**Issue:** (a) No estimate-row pin at 4k or 720p — only 1080p midpoints are asserted (I verified 4k → `~120/~66/~34` and 720p → `~19/~12/~6` manually); a transposed `quality_kbps` row would slip through. (b) The `avi` orphan row (:554-561) asserts qualitative rows but not zero `ffprobe:` calls — an unwanted probe would still fail the duration gate and render identical rows, so the pin can't detect it. (c) The ffprobe stub dispatches on `" $* "` containing ` stream=codec_type ` (:91); a fixture path containing that literal token would mis-route to the audio arm — no current fixture does. Also noted: SUMMARY claims 43 assertions; the file contains and runs 44 (`grep -c 'pass "'` and suite output agree) — trivial planning-doc drift.

---

_Reviewed: 2026-09-15T22:44:24Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
