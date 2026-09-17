---
phase: 08-non-interactive-target-size-targeting
reviewed: 2026-09-17T01:27:58Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - bin/omarchy-transcode
  - test/shell.d/transcode-quality-test.sh
findings:
  critical: 0
  warning: 1
  info: 6
  total: 7
status: resolved
---

# Phase 8: Code Review Report

**Reviewed:** 2026-09-17T01:27:58Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** resolved — WR-01 fixed (`|| true` on the `-r` toast, `bin/omarchy-transcode:435`); info items filed in deferred-items.md

## Summary

Reviewed commit `ddea5f7d` (`bin/omarchy-transcode` +230, `test/shell.d/transcode-quality-test.sh` +565) against the locked contract in `08-CONTEXT.md` / `08-RESEARCH.md` and the Phase-8 success criteria. The implementation is faithful and the mechanics verify end to end:

- `parse_target_size` (:308-324) regex-gates then normalizes (`[bB]` strip, case-up, bare→`M` append) and double-gates through `numfmt --from=iec` + `(( bytes > 0 ))`. Verified live: `0.000001M`→2 bytes (accepted, floor-refused later — safe), `99999999999999999999G`→numfmt rc 2 (rejected). Raw text never propagates; only integer bytes and the `numfmt --to=iec` canonical token do.
- `plan_target` (:337-385) orders cheap refusals before probes (≥source → duration → audio → awk math → floors). The awk formula `b*8/d/1000*0.98 - a` reproduces every pinned number (3233k@25M, 1178k@10M, 493k@5M, 685k no-audio@5M, retry 6658k→6657k). `d <= 0 → exit 1` inside awk is correct since `(( ))` can't compare floats; negative results ride the floor loop to the 720p refusal as designed — no `-nan`/negative/zero `-b:v` can reach argv.
- `transcode_video_target` (:398-466) has byte-identical `-vf`/`-c:v`/`-preset`/`-b:v` across passes, `-an`/`-f null /dev/null` on pass 1 only, `-c:a aac -b:a 192k -movflags +faststart` on pass 2 only, zero `-crf`, and no `-y`/`-n` anywhere. The `mktemp -d "${TMPDIR:-/tmp}/…"` passdir + path-baked EXIT trap + explicit `rm -rf` is correct — including the executor's real fix for the local-unbound trap bug. The retry is exactly-once, pass-2-only, gated on any byte-over, `mv`'d only on success.
- Refusal ordering matches the v1.1 hoisted-validation convention: parse rejects exit 2 in the arg loop (empty call log), semantic conflicts exit 1 post-`media_type` pre-menus, gif refusal sits at :574 (post-format-menu, pre-resolution-case — correct for menu-picked gif), budget refusals die in the planner before `output_path` and before the start toast. All probes sit right of the format/type checks; non-target runs never probe (verified by the green never-probes pin).
- v1.1 additive-diff holds: `git show` confirms removed lines are confined to metadata :6-7, `usage()`, the locals block, the menu gate, and the dispatch tail — `transcode_video`, `output_path`, `select_quality`, `video_duration`, `video_audio_kbps`, `estimate_label`, `output_size_label` bodies are untouched; `medium` argv is byte-identical (cmp-verified in the suite).
- The stub harness is genuinely pass-aware: per-pass RC knobs, synthesized `2pass-0.log`/`.mbtree` artifacts, a pass-2-exits-90 check that the pass-1 log exists at the call's own `-passlogfile`, and a per-invocation size/RC queue driven by `grep -c ' -pass 2 '` on the per-run-truncated CALLS log — sound, no counter-file needed.

Verified green: `bash -n bin/omarchy-transcode` exits 0; `bash test/shell.d/transcode-quality-test.sh` exits 0 with 82 `ok` and zero `not ok`; `./test/cli` exits 0 with 112 `ok` (metadata lint holds for the new `args=`/`examples=` lines). The two documented deviations (sparse 2 GiB fixture for `1.5G`, `5M`→`5.0M` numfmt canonicalization) are correct test-side fixes, and the third deviation (path-baked EXIT trap) is a real bug fix, correctly diagnosed.

Findings are one robustness warning (a mid-encode notification failure can kill a completed pass-1 run) and six info items; no critical defects found.

## Warnings

### WR-01: A failed `-r` notification-send aborts the run between passes

**File:** `bin/omarchy-transcode:433-436`
**Issue:** Inside `transcode_video_target`, `omarchy-notification-send -r "$notify_id" …` is a bare command in an `if` body — fully subject to `set -e`. If the notification call fails (dead daemon, busctl hiccup), the script exits 1 after pass 1 completed and before pass 2 runs: the encode's stats work is discarded, no output is produced, and the passdir is reaped. The v1.1 convention of letting notification-send failures abort is proportionate for the start toast (fails before any encode work) and the done toast (output already exists), but the new `-r` call is the only notification in the file that can kill *completed* encode work — a purely cosmetic "pass 2/2" progress update taking down a half-finished two-pass encode. The `if [[ $notify_id =~ ^[0-9]+$ ]]` guard correctly skips bad ids, but does nothing for a call that runs and fails.
**Fix:** Make the cosmetic update non-fatal:

```bash
  if [[ $notify_id =~ ^[0-9]+$ ]]; then
    omarchy-notification-send -r "$notify_id" -g <glyph> "Transcoding video…" \
      "${desc:-$(basename -- "$input") to mp4 ($resolution}, pass 2/2)" || true
  fi
```

(Alternatively accept the posture — it is consistent with how every other notification-send in this file behaves — but the cost asymmetry vs. the v1.1 call sites is new.)

## Info

### IN-01: `--target ""` rejection is in the locked contract but not pinned by a test row

**File:** `test/shell.d/transcode-quality-test.sh:872-883`
**Issue:** The must-haves (criterion 2) list `--target ""` among the exit-2 rejections, and the code handles it correctly (the empty arg survives the `(( $# > 0 ))` missing-value check, then fails the `[0-9]+` regex in `parse_target_size`). But the reject loop only covers `abc`/`-5M`/`0`/`25.5.2M` — an empty-string value is a distinct code path from a missing value and is unpinned.
**Fix:** Add `""` to the reject loop inputs (or a dedicated row asserting `run_transcode … --target ""` exits 2 with `Invalid target size` on stderr and an empty `$calls`).

### IN-02: Trap comment describes a `-d` guard the shipped trap doesn't have

**File:** `bin/omarchy-transcode:392` (comment) vs `:424` (code)
**Issue:** The block comment says "the `-d` guard keeps the persisted trap inert after return" — that describes the researched `[[ -n ${passdir:-} && -d $passdir ]]` form, but the shipped trap is a path-baked `rm -rf -- <dir>` (necessarily so — the deviation notes locals are unbound when the trap fires after an errexit unwind). Functionally identical since `rm -rf` on the already-removed dir is a silent no-op, but the comment now describes a mechanism that isn't there.
**Fix:** Adjust the comment to note the trap is inert after return because the explicit `rm -rf` already removed the directory (`rm -rf` on a missing path exits 0).

### IN-03: `plan_target`'s floor case has no `*)` arm for an out-of-vocabulary rung

**File:** `bin/omarchy-transcode:364-368`
**Issue:** If `res` were ever outside `{4k,1080p,720p}`, the first `case` leaves `floor` empty → arithmetic `0` → `(( video_kbps >= floor ))` breaks immediately → the function prints `"<bad-res> <kbps>"` as a *successful* plan; `transcode_video_target` would then refuse `Invalid video resolution` only after the start toast fired — an orphaned notification. Unreachable today (resolution is validated at :578-584 before the planner runs), but the helpers are explicitly shaped for Phase-9's `Custom size…` reuse, where an unvalidated caller could hit it.
**Fix:** Add a defensive arm to the floor `case`: `*) echo "Invalid video resolution: $res" >&2; return 1 ;;`.

### IN-04: Stub pass-2 arm records `out=` before validating the passlog

**File:** `test/shell.d/transcode-quality-test.sh:68` vs `:78`
**Issue:** The pass-2 stub arm writes `out=${!#}` to `$CALLS` before checking `[[ -n $passlog && -f ${passlog}-0.log ]] || exit 90`. A pass-2 call with a wrong/missing `-passlogfile` would still leave an `out=` line, so an `out=` grep could in principle pass for a failed encode. No current row false-greens (every `out=` assertion pairs with call-count or success assertions, and no row exercises a bad passlog), but moving the passlog check above the `out=` write models real ffmpeg more tightly (no output line for a pass that can't run).
**Fix:** Reorder so the passlog check precedes the `printf 'out=…'` line in the `*" -pass 2 "*)` arm.

### IN-05: gif under `--target` with unset resolution still fires the resolution prompt before refusing

**File:** `bin/omarchy-transcode:555-561` (prompt) vs `:574-577` (refusal)
**Issue:** For `omarchy transcode in.mov gif --target 25M` (positional gif, unset resolution) or a menu-picked gif, the resolution menu fires before the mandatory post-format-menu gif check refuses. Both paths die correctly pre-notification (pinned), but the user is asked a question whose answer is then discarded. CONTEXT lists an optional earlier check right after the format menu as discretion; it wasn't taken.
**Fix:** Optional polish — add `[[ -n $target_bytes && $format == "gif" ]]` refusal immediately after the format menu block too, keeping the mandatory check at :574 for defense.

### IN-06: Retry `mv -f` can clobber a file materialized at `$output` mid-run

**File:** `bin/omarchy-transcode:458`
**Issue:** `output_path` dedupes to a fresh name before the encode; if another process creates that exact name between the dedupe check and the retry's `mv -f -- "$passdir/retry.mp4" "$output"`, the mv silently overwrites it — slightly worse than the v1.1 TOCTOU (IN-03, phase 5) where ffmpeg would at least prompt. Same accepted-risk family (parallel-run race), recorded so the asymmetry is visible.
**Fix:** None within the locked design (`mv -f` is required precisely because the overshot first output exists). If ever revisited, `mv -n` plus a re-dedupe would close it.

---

_Reviewed: 2026-09-17T01:27:58Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_

## REVIEW COMPLETE

- Critical: 0
- Warning: 1
- Info: 6
- Total: 7
