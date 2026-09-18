---
phase: 08-non-interactive-target-size-targeting
verified: 2026-09-17T01:42:23Z
status: passed
score: 10/10 must-haves verified
covered_files:
  - .planning/REQUIREMENTS.md
  - .planning/ROADMAP.md
  - .planning/phases/08-non-interactive-target-size-targeting/08-01-PLAN.md
  - .planning/phases/08-non-interactive-target-size-targeting/08-01-SUMMARY.md
  - .planning/phases/08-non-interactive-target-size-targeting/08-CONTEXT.md
  - .planning/phases/08-non-interactive-target-size-targeting/08-REVIEW.md
  - .planning/phases/08-non-interactive-target-size-targeting/08-VALIDATION.md
  - .planning/phases/08-non-interactive-target-size-targeting/deferred-items.md
  - bin/omarchy-transcode
  - test/shell.d/transcode-quality-test.sh
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Real-clip dogfood: `omarchy transcode <real-clip> mp4 1080p --target 10M` on a clip whose source exceeds 10M"
    expected: "Two real ffmpeg passes run; the output lands under (or within one retry of) 10M, is playable, and both the start toast and done toast name the effective resolution"
    why_human: "The stub e2e and my manual stub run prove argv shape, math, step-down, retry, and ordering — not that real ffmpeg accepts the derived `-b:v`, that the 0.98 container reserve actually absorbs muxer overhead, or that x264/x265 rate control lands near budget"
  - test: "Watch the notification during a real --target run"
    expected: "ONE toast updates in place pass 1/2 → pass 2/2 (via `-p`/`-r` on the captured daemon id), then the done toast reports the stat-measured actual size; below-floor and ≥source refusals show no toast at all"
    why_human: "The stub proves call shape (`-p` → id 7 → `-r 7`) and ordering, not that the real notification daemon replaces in place; the dev shell has no exercisable daemon (per SUMMARY UAT note)"
  - test: "Interrupt or fail a real --target encode mid-pass (e.g. kill the run during pass 2, or target an unreadable/corrupt clip that passes media_type)"
    expected: "Zero `transcode-2pass.*` directories and zero `*-0.log*` files remain under $TMPDIR"
    why_human: "The pass-1/pass-2 failure rows prove the path-baked EXIT trap reaps the passdir on errexit aborts against the stub; a real signal mid-encode with the real ffmpeg binary is the residual case"
---

# Phase 8: Non-interactive `--target` size targeting Verification Report

**Phase Goal:** `omarchy transcode <video> [mp4] [res] --target <size>` accepts free-text sizes (`25M`, `1.5G`, `500K`, `25MB`; bare number = MB), derives video bitrate from probed duration (`target×8 ÷ duration × ~0.98 reserve − audio`), auto-steps resolution down the locked rungs (4k → 1080p → 720p) when the budget is tight, two-pass encodes to the budget, retries once on overshoot, and refuses honestly — naming the achievable minimum — below every floor
**Verified:** 2026-09-17T01:42:23Z
**Status:** human_needed — all 10 must-haves verified against disk with independently re-run tests plus a manual stub spot-run; the real-clip dogfood, live in-place toast update, and interrupted-real-encode passlog cleanup genuinely require the running environment
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1 | `omarchy transcode in.mov mp4 1080p --target 25M` records exactly two ffmpeg argv lines — pass 1 `-pass 1 -passlogfile <passdir>/2pass -an -f null /dev/null`, pass 2 `-pass 2 -b:v <derived>k -c:a aac -b:a 192k -movflags +faststart` — `-vf`/`-c:v`/`-preset`/`-b:v` byte-identical across passes, no `-crf`, `out=<dir>/in-1080p-25M.mp4` (SC1, SIZE-10) | ✓ VERIFIED | Implementation: pass 1 `bin/omarchy-transcode:426-428`, pass 2 `:438-440`, shared `$scale`/`$codec`/`$preset`/`${video_kbps}k` interpolation. e2e row "a --target run two-passes at the derived bitrate with byte-identical shared flags" (`test/shell.d/transcode-quality-test.sh:727-761`) green — field-extracted `-vf`/`-c:v`/`-preset`/`-b:v` compared across lines, `-crf`/`-movflags`/`-c:a` denied on pass 1, `-crf` denied on pass 2, `out=$TMPDIR/in-1080p-25M.mp4` pinned. Independently reproduced in my own stub env: 4k/10M run recorded `ffmpeg -i … -vf scale=-2:1080 -c:v libx264 -preset fast -b:v 1178k -pass 1 -passlogfile /tmp/…/transcode-2pass.XXXXXX/2pass -an -f null /dev/null` then the byte-identical-flags pass 2 |
| 2 | `--target` accepts `25M`/`25m`/`25MB`/`1.5G`/`500K`/bare `25` into integer bytes via `numfmt --from=iec`, canonicalizes to a `numfmt --to=iec` filename token (`-25M`/`-1.5G`/`-5.0M`), and rejects `abc`/`-5M`/`0`/`25.5.2M`/missing/empty — exit 2, stderr, before any side effect (SC2, SIZE-10, D-00a) | ✓ VERIFIED | `parse_target_size` :308-324: regex `^[0-9]+(\.[0-9]+)?([kKmMgG][bB]?)?$` :311, `[bB]`-strip/case-up/bare→`M` normalize :314-316, `numfmt --from=iec` belt :318, `(( bytes > 0 ))` :320. Flag arm :481-486: missing-value `return 2`, `parse_target_size` failure `|| return 2`, `target_token=$(numfmt --to=iec …)` :485. e2e: accepts row :794-813 (incl. 2 GiB sparse fixture for 1.5G ≥source avoidance, `500K` accept-signaled by reaching the planner), rejects row :872-883, missing-value :816-825 — all green. Manual spot-run: `--target ""` → exit 2 `Invalid target size:` with zero stub calls (call log never even created); `--target=25M` → `Unknown option` + usage, exit 2 |
| 3 | Video bitrate derives as `target_bytes × 8 ÷ duration ÷ 1000 × 0.98 − audio_kbps` in `awk -v` with `%d` truncation; `d <= 0 → exit 1` inside awk; negative/zero results ride the floor loop to the 720p refusal — no negative, zero, or `-nan` `-b:v` reaches argv (SC4, SIZE-10/SIZE-14) | ✓ VERIFIED | awk :357-360 — `if (d <= 0) exit 1; printf "%d", b * 8 / d / 1000 * 0.98 - a`; captures on own lines :350-352 (never `local x=$(…)`). Worked numbers independently recomputed: 26214400×8÷60÷1000×0.98−192 = 3233.35→`3233k`; 10M→`1178k`; 5M→`493k`; no-audio 5M→`685k`; retry 6658×52428800÷52428801→`6657k` — all match the pinned assertions. Sweep row :988-990 greps accumulated argv for `-b:v -`/`-b:v 0k`/`-nan` — empty |
| 4 | Planner picks the highest rung whose floor fits — `video_kbps >= floor` inclusive at locked 2000/800/400 kbps for 4k/1080p/720p — writes the effective rung into `resolution` before `output_path`, so filename + both toasts name the actual resolution with step-down disclosure (SC3, SIZE-13) | ✓ VERIFIED | Floor case :364-368, inclusive `(( video_kbps >= floor )) && break` :369, step table :370-372; `plan_target` call :612 → `read -r resolution video_kbps` :613 → `output_path` :616. Toast desc built :623-627 with `— stepped down from $requested_resolution` conditional. e2e green: 4k→1080p@10M (`-b:v 1178k`, toast names `1080p` + `stepped down from 4k` + `10M`, done toast `Transcoded to 1080p`) :830-842; 4k→720p@5M (`-b:v 493k`, `in-720p-5.0M.mp4`) :847-854; stays-at-4k boundary @25M (3233 ≥ 2000, x265 slow, `in-4k-25M.mp4`) :858-867. Manual spot-run reproduced the 4k→1080p step-down with disclosure |
| 5 | Audio fixed `-b:a 192k` on every pass-2/retry line — no step-down ladder; below the 720p floor (incl. audio-only-exceeds) the run refuses naming the computed achievable minimum `(400+audio)×dur×125` rendered `~N MB`; `target ≥ source` refuses naming both sizes + tier pointer; failed/`N/A`/zero duration refuses identically pre-notification (SC4, SIZE-13/SIZE-14) | ✓ VERIFIED | `-b:a 192k` literal on pass 2 :440 and retry :457; refusal `*)` arm :373-380 computes `min_label` via awk `(400 + a) * d * 125 / 1048576` :376-377 → `Cannot fit under … smallest achievable is ~4 MB` (verified live). ≥source gate :341-345 precedes both probes (e2e :996-1006 pins zero `ffprobe:` lines; manual run confirmed empty log). Duration refusals :350-351/:361. e2e green: below-floor 4M/2M :960-974, audio-only 1M :979-991, three probe-failure shapes :1011-1042 — each pre-notification with staged call-log emptiness |
| 6 | `--target`+positional quality exits 1 naming both; `--target`+gif refuses (positional AND menu-picked — check sits post-format-menu at :574, pre-resolution-case); `--target`+picture refuses; CLI `--target` skips `select_quality` while an unset resolution still prompts as the ceiling (SC5, SAFE-02) | ✓ VERIFIED | Quality conflict :524-527 (first inside the `[[ -n $quality ]]` gate — fires even for picture+quality+target); picture refusal :542-545; gif refusal :574-577 after format menu :547-553, before resolution case :578; menu gate `&& -z $target_bytes` :602; resolution prompt :555-561 untouched. e2e green: conflict row :887-897 (exit 1, stderr names `--target` and `low`, empty log), positional gif :901-910, menu-picked gif :915-930 (`menu-select:`-only log, refuses on gif check not `Invalid video resolution`), picture :934-943, ceiling prompt :947-954 (4k pick on 5M → `in-720p-5.0M.mp4`), menu-skip :785-788 |
| 7 | Any byte-over triggers exactly one pass-2-only re-encode at `video_kbps₂ = video_kbps₁ × target_bytes ÷ actual_bytes`, passdir-sibling output `mv`'d onto `$output` only on success — never a loop, no `-y`/`-n`, failed retry preserves the overshot first output, done toast reports stat-actual either way (SC6, SIZE-15) | ✓ VERIFIED | Stat gate `(( actual > target_bytes ))` :450-451; `retry_kbps` awk :452-453; `> 0` guard :454; `if ffmpeg … "$passdir/retry.mp4"; then mv -f -- … "$output"; fi` :455-459 — single `if`, no loop. e2e green: byte-over retry :1068-1098 (exactly 3 ffmpeg calls, `-b:v 6657k`, one shared passlogfile, output lands 4 MiB, done toast `(4 MB)`); at/under never retries :1103-1120 (target, target−1 pins); still-over retry never loops :1124-1134; failed retry preserves 70M+1 output + reports `(70 MB)` :1138-1153. Manual spot-run reproduced: 20M output on 10M target → one retry at `617k` → `mv` → done toast `(19 MB)` actual |
| 8 | Passlogs live in per-run `mktemp -d` under `TMPDIR` with EXIT trap + explicit `rm -rf` after the retry block; pass-1 or pass-2 failure leaves zero `*-0.log*`/passdir artifacts; re-run dedupes to `-2`; parallel runs can't share a passlog (SC7, D-00g) | ✓ VERIFIED | `passdir=$(mktemp -d "${TMPDIR:-/tmp}/transcode-2pass.XXXXXX")` :423; path-baked `trap "rm -rf -- $(printf '%q' "$passdir")" EXIT` :424 (the executor's real fix — locals unbound at trap fire after errexit unwind); explicit `rm -rf "$passdir"` :465 after the retry (retry reuses the passlog). e2e green: hygiene pins :1093-1096 (success), :1148-1151 (failed retry), :1170-1173 (pass-1 fail — 1 ffmpeg call, 1 toast, clean), :1190-1193 (pass-2 fail — 2 calls, no done toast, clean); dedupe-with-token row :1198-1203 (`in-1080p-25M-2.mp4`). Manual spot-run: `find $TMPDIR -name '*2pass*'` empty after a full run incl. retry |
| 9 | The stub harness is pass-aware — ` -pass 1 `/` -pass 2 ` argv dispatch, synthesized `-0.log` artifacts, `FAKE_PASS1_RC`/`FAKE_PASS2_RC` per-pass RC, `FAKE_OUT_BYTES2` second-output queue, notification `-p` arm echoing an id, `TMPDIR` exported — and every v1.1 pin still passes (SC8) | ✓ VERIFIED | Stub dispatch :42-100: pass-1 arm records argv + synthesizes `passlog-0.log`/`.mbtree` :43-57; pass-2 arm requires the pass-1 log at its own `-passlogfile` (`exit 90` :78), per-invocation size queue via `grep -c ' -pass 2 '` :79-83, RC list :87-90; `*)` arm preserves single-pass/magick behavior :93-99. Notification stub `-p`→`7` :112-114. `run_transcode` exports `TMPDIR` :184. All 82 assertions green including every v1.1 row (byte-identical medium argv :221-225, never-probes :473-483/:1055-1059, no-overwrite-flag :420-423/:1213-1216) |
| 10 | Ordering pinned: `--target` run records exactly two `ffprobe:` lines (duration + audio-presence) and probes run only after format/type checks; positional-gif refusal leaves no `notification:`/`ffmpeg`; menu-picked-gif leaves only `menu-select:`; post-probe refusals leave `ffprobe:` but zero `notification:`/`ffmpeg` (SAFE-02 ordering) | ✓ VERIFIED | `plan_target` call :612 sits after all validation :563-600 and menus; probes inside `plan_target` :350-352 only. e2e green: probe-count twin `grep -c '^ffprobe:' == 2` :779-781; menu-skip :785-788; staged emptiness on every refusal row (verified row-by-row above). Manual spot-run confirmed ordering: `ffprobe:`×2 → `-p` toast → ffmpeg×2 → `-r` toast → done toast |

**Score:** 10/10 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `bin/omarchy-transcode` | Three new helpers (`parse_target_size`, `plan_target`, `transcode_video_target`) in one contiguous block between `output_size_label` and `main`, plus colocated `main()` hunks and synced metadata/usage | ✓ VERIFIED | `parse_target_size` :308-324, `plan_target` :337-385, `transcode_video_target` :398-466 — contiguous between `output_size_label` (:292-300) and `main` (:468); locals :471-472; `--target` arm :481-486; refusal matrix :524-527/:542-545/:574-577; menu gate :602; planner+write-back :610-614; `output_path "${target_token:-$quality}"` :616; dispatch :619-629 with `-p` toast :628; metadata :6-7; usage :14/:21. `bash -n` exit 0 |
| `test/shell.d/transcode-quality-test.sh` | Pass-aware ffmpeg stub + notification `-p` arm + `TMPDIR` export + ~40 new rows, all v1.1 pins unchanged | ✓ VERIFIED | Pass dispatch :42-100, `-p` arm :112-114, `TMPDIR` env :184, FAKE knobs honored throughout; 82 `ok` lines, zero `not ok` on independent re-run |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `main()` arg loop | `parse_target_size()` | `--target)` arm :481-486: `shift`; missing-value → `return 2`; `target_bytes=$(parse_target_size "$1") \|\| return 2`; `target_token=$(numfmt --to=iec "$target_bytes")` | ✓ WIRED | Raw text validated to integer bytes at the boundary; only bytes + canonical token propagate (verified live: `--target ""` exit 2, zero stub calls) |
| `main()` planner block | `plan_target()` → resolution write-back → `output_path()` | `plan=$(plan_target "$input" "$target_bytes" "$requested_resolution")` :612 on its own line (nonzero aborts via `set -e`); `read -r resolution video_kbps <<<"$plan"` :613; `output_path "$input" "$format" "$resolution" "${target_token:-$quality}"` :616 | ✓ WIRED | Filename + both toasts name the effective rung — proven by the step-down e2e rows and the manual run's `in-1080p-10M.mp4` + disclosure toast |
| `main()` dispatch | `transcode_video_target()` + `omarchy-notification-send -p`/`-r` | `notify_id=$(omarchy-notification-send -p -g … "…pass 1/2)")` :628; `transcode_video_target "$input" "$resolution" "$output" "$video_kbps" "$target_bytes" "$notify_id" "$target_desc"` :629; `-r "$notify_id"` guarded by `if [[ $notify_id =~ ^[0-9]+$ ]]` :433-436, WR-01 `|| true` at :435 | ✓ WIRED | Manual run recorded `-p` start toast → `-r 42` pass-2/2 replacement between the passes, correct ordering |
| test stub ffmpeg | pass-aware argv recording | `case " $* " in *" -pass 1 "* \| *" -pass 2 "* \| *)` :42-100 — pass 1 synthesizes passlog artifacts from `-passlogfile`; pass 2 requires them (:78), records `out=`, sizes via `FAKE_OUT_BYTES`/`FAKE_OUT_BYTES2` queue, RC via `FAKE_PASS2_RC` list | ✓ WIRED | Passlog-backed pass 2 (exit-90 gate) means argv can never claim a two-pass encode the logs don't back |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `bin/omarchy-transcode` | `$1` → `target_bytes` (parse_target_size) → `target_token` (numfmt); `video_duration`/`video_audio_kbps` → awk → `video_kbps`; floor loop → `resolution`; `stat $output` → `actual` → `retry_kbps`; `stat $output` → `output_size_label` → done toast | caller argv + real probes + real stat | Yes — every recorded argv/out/notification line in e2e and the manual run derives from the caller-supplied size and the probed values; the done toast reports stat-measured bytes, never the request | ✓ FLOWING |

### Prohibitions (negative checks — all empirically verified)

| Prohibition | Status | Evidence |
| ----------- | ------ | -------- |
| No `-crf` on any `--target` ffmpeg line | ✓ HELD | `sed -n '398,466p'` of `transcode_video_target` — zero `crf` matches; e2e pins `! grep -F -- '-crf'` on both pass lines :740-752; `-crf` survives only in `transcode_video`'s tier arms :136/:138 |
| No `-y`/`-n` anywhere — dedupe + passdir-sibling retry is the whole collision policy | ✓ HELD | `grep -nE '(^|[[:space:]])-[yn]([[:space:]]|$)'` hits only `[[ -n … ]]` tests and a comment; e2e cumulative scan :420-423 + :1213-1216 empty across every accumulated ffmpeg line incl. pass/retry lines |
| Never overwrite/delete the input; every write targets a derived `output_path` name or the `mktemp -d` passdir; `mv -f` targets `$output` only | ✓ HELD | `mv -f -- "$passdir/retry.mp4" "$output"` :458 — `$output` is always `stem-<res>-<token>.<fmt>` deduped via `[[ -e \|\| -L ]]` :68; no code path writes `$input` |
| Never report the requested target as achieved — done toast reports stat-actual; refusals name the computed minimum | ✓ HELD | `output_size_label "$output"` :635 stat-measures post-retry; e2e `(4 MB)`/`(70 MB)`/`(60 MB)` rows pin actual-vs-target honesty; floor refusal prints `~$min_label` computed :376-378 |
| Raw `--target` text never reaches argv or a filename | ✓ HELD | Only `target_bytes` (integer) and `target_token` (numfmt canonical) exist past :484-485; regex+numfmt+positive gates :311-321 |
| v1.1 pins hold: `medium` argv byte-identical; non-target runs never probe; additive-diff on existing function bodies | ✓ HELD | `git show ddea5f7d` — the only removed script lines are metadata :6-7, `usage()` 2 lines, the menu-gate line, the `output_path` line, and the 2 dispatch lines; `transcode_video`/`output_path`/`select_quality`/`video_duration`/`video_audio_kbps`/`estimate_label`/`output_size_label` bodies untouched. e2e `cmp` rows :215-225/:479-482 + never-probes :474-476/:1056-1058 green |
| Refusals die before menus and before the start notification | ✓ HELD | Parse rejects in arg loop (empty log, verified live); quality/picture checks :524-545 before format menu :547; gif check :574 pre-notification; planner refusals :612 before toast :628 — staged-emptiness pins green on every row |
| No `-fs`, no retry loop, no audio ladder, no codec switching (REQUIREMENTS out-of-scope) | ✓ HELD | `grep -- '-fs\|-nostdin'` empty; single `if` retry :451-461, no loop; `-b:a 192k` literal on both lines; codec stays resolution-keyed :413-419 |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full stub e2e | `bash test/shell.d/transcode-quality-test.sh` | 82/82 `ok -`, zero `not ok`, exit 0 | ✓ PASS |
| Syntax | `bash -n bin/omarchy-transcode` | exit 0 | ✓ PASS |
| Metadata lint + routing | `./test/cli` | exit 0 (all `ok`, incl. metadata pins on the new `args=`/`examples=` lines) | ✓ PASS |
| Full shell suite | `./test/shell` | 7/240 files failed — exactly the documented environmental set (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths); transcode-quality green inside | ✓ PASS |
| Manual stub spot-run (independent harness) | `omarchy-transcode in.mov mp4 4k --target 10M` @dur=60 | step-down to 1080p, `-b:v 1178k` on both passes, `-p`→`-r 42` toast sequence, overshoot→one retry at `617k`→`mv`→done toast `(19 MB)`, zero `*2pass*` leftovers | ✓ PASS |
| Empty `--target ""` (IN-01 gap check) | manual run | exit 2, `Invalid target size:` on stderr, zero stub calls — the contract-locked rejection works even though no test row pins it | ✓ PASS |
| `--target=25M` (= form) | manual run | `Unknown option` + usage, exit 2 — matches `--path` no-`=` convention | ✓ PASS |
| `≥source` / below-floor / `=form` refusals | manual runs | 200M→exit 1 naming both sizes + tier pointer pre-probe; 4M@60s→exit 1 `smallest achievable is ~4 MB` post-probe; both with correct staged call logs | ✓ PASS |

### Probe Execution

No probes declared or discovered for this phase — N/A.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| SIZE-10 | 08-01 | Free-text `--target` parsing + two-pass encode to byte budget + actual-size completion notification | ✓ SATISFIED | Truths 1, 2, 3 + e2e happy-path/parse rows + manual spot-run. REQUIREMENTS.md:12,51 |
| SIZE-13 | 08-01 | Auto-step-down to highest fitting rung; filename + both notifications name actual resolution; below-every-rung refusal names achievable minimum | ✓ SATISFIED | Truths 4, 5 + step-down/refusal rows. REQUIREMENTS.md:13,52 |
| SIZE-14 | 08-01 | Fixed `-b:a 192k`; refuse early when budget can't fit audio + viable video | ✓ SATISFIED | Truth 5 + audio-only 1M row + `-b:a 192k` literals :440/:457. REQUIREMENTS.md:14,53 |
| SIZE-15 | 08-01 | Exactly one tightened retry on overshoot; report actual either way; never a silent loop | ✓ SATISFIED | Truth 7 + four retry rows + manual reproduction. REQUIREMENTS.md:15,54 |
| SAFE-02 | 08-01 | `--target` ⊥ quality arg; refuses gif/picture; fails fast before start notification on missing/unparseable/dead-probe | ✓ SATISFIED | Truths 6, 10 + refusal-matrix rows. REQUIREMENTS.md:23,56 |

No orphaned requirements: REQUIREMENTS.md maps exactly SIZE-10/13/14/15/SAFE-02 to Phase 8, all declared in the plan.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | — | — | None. No TBD/FIXME/XXX/TODO/HACK markers in the two modified files; no stub patterns. WR-01 was fixed post-review (`|| true` on the `-r` toast, `bin/omarchy-transcode:435`, commit `06ad1096`). All six info items correctly dispositioned in `deferred-items.md` — IN-01 (`--target ""` unpinned) verified working empirically; IN-03 (floor `case` `*)` arm) confirmed unreachable today (resolution validated :578-584 before the planner); IN-04/IN-05/IN-06 are harness-fidelity/ordering/accepted-TOCTOU notes, none blocking |

### Human Verification Required

The stub harness proves argv shape, math, ordering, retry bound, and passdir lifecycle, but the real encoder, the live notification daemon, and real signal-driven aborts cannot be exercised programmatically:

### 1. Real-clip `--target` dogfood (SIZE-10/SIZE-15 — the meaningful item)

**Test:** `omarchy transcode <real-clip> mp4 1080p --target 10M` on a clip whose source exceeds 10M
**Expected:** Two real ffmpeg passes run; the output lands under (or within one retry of) 10M, is playable, and both toasts name the effective resolution
**Why human:** Stubs prove the derived `-b:v` reaches argv correctly, not that real ffmpeg accepts it or that the 0.98 reserve absorbs actual container overhead — the "does a real 25M encode land near 25M" question is inherently about the real encoder's rate control

### 2. Live in-place toast update across the two passes (D-08)

**Test:** Watch notifications during a real `--target` run
**Expected:** ONE toast updates in place pass 1/2 → pass 2/2 via the captured daemon id, then the done toast reports the stat-measured actual size; below-floor and ≥source refusals show no toast
**Why human:** The stub proves the `-p` → id → `-r <id>` call shape and ordering, not that the real notification daemon replaces in place; no exercisable daemon exists in this environment

### 3. Passlog cleanup on a real interrupted/failed encode (D-00g)

**Test:** Kill a real `--target` run mid-pass-2 (or feed a corrupt clip that passes `media_type` but fails probing/encoding), then `find $TMPDIR -name 'transcode-2pass.*' -o -name '*-0.log*'`
**Expected:** Zero artifacts remain
**Why human:** The pass-1/pass-2 failure e2e rows prove the path-baked EXIT trap reaps the passdir on errexit aborts against the stub; a real signal hitting real ffmpeg mid-encode is the residual

### Gaps Summary

No gaps. All ten must-have truths verified goal-backward against the working tree: the 82-assertion stub e2e re-ran green, `bash -n` and `./test/cli` exit 0, `./test/shell` fails only on the 7 known environmental files, and an independently-built stub harness reproduced the happy path, step-down, overshoot retry, honest actual-size toast, and passdir cleanup. The WR-01 review fix (`|| true` at `bin/omarchy-transcode:435`, commit `06ad1096`) is in place; `git show ddea5f7d` confirms the additive-diff constraint held (removed lines confined to metadata/usage/gate/dispatch). Status is `human_needed` solely because real-encode acceptance, the live `-r` toast replace, and real-signal passlog cleanup cannot be proven without the running environment.

---

_Verified: 2026-09-17T01:42:23Z_
_Verifier: the agent (gsd-verifier)_

## VERIFICATION COMPLETE

10/10 must-haves verified, 3 human items
