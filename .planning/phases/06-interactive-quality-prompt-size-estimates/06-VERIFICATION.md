---
phase: 06-interactive-quality-prompt-size-estimates
verified: 2026-09-15T22:56:52Z
status: human_needed
score: 10/10 must-haves verified
covered_files:
  - .planning/REQUIREMENTS.md
  - .planning/phases/06-interactive-quality-prompt-size-estimates/06-01-PLAN.md
  - .planning/phases/06-interactive-quality-prompt-size-estimates/06-01-SUMMARY.md
  - .planning/phases/06-interactive-quality-prompt-size-estimates/06-CONTEXT.md
  - .planning/phases/06-interactive-quality-prompt-size-estimates/06-REVIEW.md
  - bin/omarchy-transcode
  - test/shell.d/menu-select-test.sh
  - test/shell.d/transcode-quality-test.sh
covered_digest: "v1:sha256:158427fbf35928695c84cf5cfd9fb5c2e7258f5a583950ba368047270100742f"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Open the quality menu in the running UI (`omarchy transcode <clip> mp4 1080p` after `omarchy-restart-shell`, or `wtype -k Return` to accept the default)"
    expected: "Cursor sits on `medium`; the three rows show `CRF N · ~N MB` subtexts un-elided at ~300px card width with uniform `detailRowHeight`; Enter picks medium"
    why_human: "Rendered pre-highlight, elision, and row heights are running-shell properties per agents/skills/visual-verification.md; the dev shell loads the packaged /usr/share/omarchy tree, and the stub harness proves argv, not pixels (VALIDATION.md Manual-Only table; SUMMARY UAT item a)"
  - test: "Estimate-vs-actual dogfood: transcode 2–3 varied real clips through the quality menu and compare the shown `~N MB` against the real output size"
    expected: "Each estimate lands within ~2× of the actual output (CRF variance is expected — the check is that estimates land inside it, not that they are exact)"
    why_human: "Requires real ffprobe/ffmpeg runs on real media; stubs pin the math against fixed durations, not real-clip bitrate behavior (SUMMARY UAT item b)"
  - test: "Nautilus multi-select: select 2+ videos in Files → Transcode → complete the flow"
    expected: "The quality prompt appears once per file (locked behavior — verify understood, not broken)"
    why_human: "Real Nautilus/session path; `transcode.py` invokes path-only so the interactive chain runs per file — unverifiable without the live session (SUMMARY UAT item c)"
  - test: "Partial positionals: `omarchy transcode <clip> mp4`"
    expected: "The resolution prompt fires, then the quality prompt fires (D-00i two-prompt chain)"
    why_human: "The single-pick stub answers every menu invocation identically, so the sequential `-z` chain cannot be driven end-to-end in the harness; the plan deliberately deferred this to UAT (SUMMARY UAT item d; 06-01-PLAN flagged assumptions)"
---

# Phase 6: Interactive quality prompt + size estimates Verification Report

**Phase Goal:** The video transcode flow gains a "Select quality" step after format+resolution whose rows carry `~N MB` estimate subtexts for mp4 (ffprobe duration × tier bitrate table + 192k audio) and fps subtexts for gif, with `medium` pre-highlighted via `--default-index 1` — pictures see no new prompt
**Verified:** 2026-09-15T22:56:52Z
**Status:** human_needed — all 10 must-have truths verified against disk and independently re-run tests; the running-UI render, real-clip calibration, Nautilus session, and partial-positionals two-prompt chain genuinely require the live environment
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1 | `omarchy transcode in.mov mp4 1080p` (interactive video, quality unset) fires `Select quality` AFTER the resolution prompt with `\t<tier>\t<subtext>` rows and `omarchy-menu-select ... -- --default-index 1` so `medium` is pre-highlighted (QUAL-01, D-00a/b/c, D-01; ROADMAP SC1, SC3) | ✓ VERIFIED | Prompt block `bin/omarchy-transcode:365-367` sits between the resolution `fi` (:363) and `output_path` (:369); rows built at :271 as `$'\t'"$tier"$'\t'"$subtext"` (leading tab = empty glyph, matching the `glyph⇥label⇥subtext` contract documented in `bin/omarchy-menu-select:9-14`); menu call :274 carries `-- --default-index 1` (only `default-index` match in the file). e2e re-ran green: "the quality menu fires with CRF N · ~N MB rows and medium pre-highlighted" asserts `Select quality`, `--default-index 1`, and all three tab-joined rows in recorded argv. The four-step file→format→resolution→quality chain is structurally ordered by the sequential `-z` blocks (:325-367); the unset-resolution sub-chain routes to human item 4 |
| 2 | The mp4 estimate is `bytes = dur × (kbps + audio) × 125` rendered `~N MB` at 1–2 sig figs with no decimal; locked table 720p 2500/1500/700, 1080p 5500/3000/1400, 4k 16000/9000/4500 kbps + audio term (192, or 0 only on proven no-audio) (SIZE-01, D-00e/h; ROADMAP SC2) | ✓ VERIFIED — with documented caveat | `estimate_label` awk :230-239 computes `dur * (kbps + audio) * 125` → `mb` → 2-sig-fig `r` → `~%d MB`; `quality_kbps` :217-223 holds the exact locked table; `video_audio_kbps` :172-178 returns 0 only on a successful probe reporting no `audio` line, else 192. e2e pins green: 60 s/1080p → `~41`/`~23`/`~11`, 157 s → `~110`/`~60`/`~30`, no-decimal `~[0-9]*\.[0-9]` absence pin, `FAKE_AUDIO=no` → `~39`/`~21`/`~10`. **Caveat (REVIEW WR-01, independently reproduced):** `printf "~%d MB", r` floors instead of rounding below 10 MiB — `dur=1 kbps=15938` (1.90 MiB) prints `~1 MB` (should be `~2`), `dur=9 kbps=9000` (9.66 MiB) prints `~9 MB` (should be `~10`). Assessed as non-blocking: bounded ≤~1 MB understatement inside the estimate's own ±2× envelope, strictly conservative (never overstates — consistent with the honesty contract), confined to the [1.5,10) MiB band. See Anti-Patterns |
| 3 | A tier whose estimate exceeds `stat -c %s` of the input renders `larger than source` on that row only (D-02) | ✓ VERIFIED | `estimate_label` :232 `if (src != "" && bytes > src) { print "larger than source"; exit }`; `src_bytes` regex-gated `^[0-9]+$` at :254-255 (empty disables the comparison, per flagged assumption). e2e green: 15 MiB fixture degrades high+medium rows but keeps low `~11 MB`; 1 KiB fixture degrades all three — per-row, not per-menu |
| 4 | ffprobe `N/A`/non-numeric or hard failure makes ALL THREE rows qualitative (`Best quality`/`Balanced`/`Smallest file`) — never a subtext/no-subtext mix, never a `set -e` abort (D-03, T-06-03) | ✓ VERIFIED | `video_duration` :164-166 `|| true` + `^[0-9.]+$` gate returns 1 on junk; `duration=$(...) || duration=""` :253 keeps the failure non-fatal; the `else` arm :265-269 supplies the three qualitative literals for every tier, so all rows always carry a subtext. e2e green: `FAKE_DURATION=N/A` and `FAKE_PROBE_RC=1` rows both render all three fallbacks, contain zero `~`, and still reach `ffmpeg` — cosmetic degrade, no abort |
| 5 | gif rows carry `15 fps`/`10 fps`/`5 fps` subtexts and ffprobe is never spawned on the gif path (D-00f, D-00g) | ✓ VERIFIED | Probes are gated `[[ $format == "mp4" ]]` at :252; the gif arm :260-261 uses `quality_token gif` → `15 fps`/`10 fps`/`5 fps` (:205-209). e2e green: "gif rows carry fps subtexts and never probe the input" — asserts all three fps subtexts, zero `~`, and zero `ffprobe:` lines in `$calls` |
| 6 | The pick's subtext is stripped at the first tab (`${selection%%$'\t'*}`) and re-validated `high\|medium\|low` inside `select_quality` before it can reach `case`/filename/ffmpeg (D-00d, T-06-02; ROADMAP SC4) | ✓ VERIFIED | Strip :276, re-validation `case` :277-283 emits `Invalid video quality: $selection` + `return 1` inside the helper — before the notification boundary (:372). e2e green: `low\tCRF 28 · ~11 MB` pick → `-crf 28` + `in-1080p-low.mp4` (subtext never reached matching); `bogus\tjunk` pick → non-zero, `Invalid video quality` on stderr, menu/probe lines present but zero `notification:`/`ffmpeg` lines |
| 7 | Non-interactive callers (4th positional supplied) and picture inputs never spawn ffprobe or the quality menu — gated `[[ $type == "video" && -z $quality ]]` (D-00g, QUAL-03; ROADMAP SC5, SC6) | ✓ VERIFIED | Gate :365 — `type == "video"` excludes pictures, `-z $quality` excludes 4-positional callers; probes live only inside `select_quality`. e2e green: "a four-positional run never prompts or probes" (zero `menu-select:`/`ffprobe:` + literal medium argv) and "a picture run never prompts for quality or probes" (zero of both, magick still resizes) |
| 8 | A `medium` pick (the Enter-default row) produces ffmpeg argv byte-identical to Phase-5 positional `medium` — `-preset fast -crf 23 -c:a aac -b:a 192k -movflags +faststart` at 1080p — and the unsuffixed `in-1080p.mp4` (ROADMAP SC3) | ✓ VERIFIED | e2e `cmp -s` rows green: menu-pick `medium\tCRF 23 · ~23 MB` argv equals both the explicit-`medium` positional argv and the `%q`-built literal `expected-medium-argv` line; `out=…/in-1080p.mp4` unsuffixed. `output_path` :61-63 keeps `medium` unsuffixed; `transcode_video` tier case :122-130 unchanged |
| 9 | Esc/empty selection propagates exit 1 through the command substitution and aborts silently — same semantics as the sibling format/resolution prompts (D-00i edge) | ✓ VERIFIED | `select_quality` :274 `|| return` propagates the menu's exit 1; the failed command substitution aborts under `set -e` (:9) identically to :351/:353/:359/:361. e2e green: `FAKE_PICK=""` → non-zero run, zero `notification:`/`ffmpeg` lines — aborts before the notification |
| 10 | Decision map honored: D-00a quality last; D-00b `-- --default-index 1`; D-00c `\t<label>\t<subtext>`; D-00d `%%$'\t'*` strip; D-00e bitrate table; D-00f gif fps-only; D-00g probe scoping; D-00h `~`+1–2 sig figs; D-00i fires on ANY unset-quality interactive path incl. partial positionals; D-01 `CRF N · ~N MB`; D-02 per-row `larger than source`; D-03 all-qualitative fallback; D-04 empty glyph field | ✓ VERIFIED | Each decision verified at the code lines cited in truths 1-9. D-00i partial-positionals sub-case: the `-z` gates are sequential and identical in shape to the proven resolution block, but the two-prompt chain itself is stub-undrivable → human item 4. D-00h has the WR-01 caveat noted on truth 2. Helpers correctly placed between `copy_to_clipboard` (:156) and `main` (:287) — clear of the `transcode_video`↔`copy_to_clipboard` PR #6698 insertion zone |

**Score:** 10/10 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `bin/omarchy-transcode` | six helpers (`video_duration`, `video_audio_kbps`, `quality_token`, `quality_kbps`, `estimate_label`, `select_quality`) between `copy_to_clipboard` and `main`, plus the `type == video && -z $quality` prompt block in `main()` | ✓ VERIFIED | Helpers at :162/:172/:185/:217/:229/:247 — all inside the :157-286 gap (copy_to_clipboard ends :156, main opens :287); prompt block :365-367; usage() names the quality step :17; `bash -n` clean. Substantive (not stubs), all wired from `select_quality`/`main` |
| `test/shell.d/transcode-quality-test.sh` | dual-mode `omarchy-menu-select` stub (FAKE_PICK), arg-dispatched `ffprobe` stub (FAKE_DURATION/FAKE_AUDIO/FAKE_PROBE_RC), `truncate -s` sized fixtures, interactive-path assertion matrix; Phase-5 rows keep passing | ✓ VERIFIED | Dual-mode stub :71-79 (`${FAKE_PICK+x}` distinguishes unset-tripwire from set-answer, empty = Esc, `printf '%s'` no-newline fidelity); arg-dispatched ffprobe stub :88-106 (` stream=codec_type ` token → audio arm, else duration arm); `truncate -s 120M` fixture :128 + per-row `15M`/1024 fixtures; 44 `pass` assertions, re-ran 44/44 green standalone and inside `./test/shell` |
| `test/shell.d/menu-select-test.sh` (deviation) | Phase-4 `--default-index` caller pin re-scoped so omarchy-transcode is the sanctioned first caller | ✓ VERIFIED | `fbe56e4c` re-scopes the sweep at :118-121 to exclude `/omarchy-transcode$` — tripwire preserved for any *other* new caller; 11/11 green inside `./test/shell` |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `main()` | `select_quality()` | `quality=$(select_quality "$input" "$format" "$resolution")` inside `if [[ $type == "video" && -z $quality ]]` (:365-366), after the resolution block, before `output_path` (:369) | ✓ WIRED | Ordering verified in code and by e2e (menu fires only on the unset-quality video path); estimates key on format × resolution because the block sits after both prompts |
| `select_quality()` | `omarchy-menu-select --default-index` (Phase-4 plumbing) | `omarchy-menu-select "Select quality" "${rows[@]}" -- --default-index 1` :274 | ✓ WIRED | Sole `default-index` call site in the file; menu-select's flag arm and `label⇥subtext` return contract verified intact at `bin/omarchy-menu-select:54-57` and doc comment :9-14; Phase-4 regression green (menu-select-test.sh 11/11 with re-scoped pin) |
| `select_quality()` return | `output_path()` + `transcode_video()` | printed label-only pick → `quality` → `output_path "$input" "$format" "$resolution" "$quality"` (:369) suffix/dedupe → `transcode_video` 5th arg (:373) | ✓ WIRED | e2e `low\t…` pick proves end-to-end: `-crf 28` argv + `-low` filename suffix; `medium` pick → literal medium argv + unsuffixed name |
| `estimate_label()` | awk estimate math | `awk -v dur/kbps/audio/src 'BEGIN { bytes = dur * (kbps + audio) * 125; … "larger than source"; … "~%d MB" }'` :230-239 | ✓ WIRED | `-v` inputs regex-gated upstream (`^[0-9.]+$` duration :166, `^[0-9]+$` src_bytes :255, table/audio constants) — T-06-01 boundary held; live-reproduced outputs match all pins plus the WR-01 floor caveat |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `select_quality`/`estimate_label` | `duration` → `bytes` → `subtext` → `rows[@]` → menu argv | `ffprobe -show_entries format=duration` on the real input (:164-165), `stat -c %s` (:254), `video_audio_kbps` probe (:174) | Yes — real probe bytes drive the estimate; failure degrades to qualitative literals, never a fabricated number | ✓ FLOWING |
| `select_quality` | `selection` → strip → re-validate → `printf` → `main`'s `quality` | `omarchy-menu-select` return across the tempfile handshake | Yes — the pick string flows through strip+case before reaching `output_path`/`transcode_video` | ✓ FLOWING |

### Prohibitions (negative checks — all empirically verified)

| Prohibition | Status | Evidence |
| ----------- | ------ | -------- |
| Never show a number the tool can already disprove (per-row `larger than source`; gif never carries MB subtexts) | ✓ HELD | :232 src-bytes comparison + gif arm has no estimate path; e2e 15 MiB/1 KiB rows green |
| Subtext never reaches `case`, `output_path`, or ffmpeg argv | ✓ HELD | Strip :276 + re-validation :277-283; foreign-label e2e row proves rejection pre-notification |
| Probe hiccup never kills the flow (`|| true`-guarded + regex-gated) | ✓ HELD | :164-165 `|| true`, :174 `if`-guarded, :253 `|| duration=""`, :254 `|| true`; N/A + RC=1 e2e rows reach ffmpeg |
| Never mix subtext/no-subtext rows | ✓ HELD | `rows+=(…$'\t'"$subtext")` :271 fires for all three tiers in every branch; fallback supplies literals :265-269 |
| ffprobe never runs outside `type == video && -z $quality` | ✓ HELD | Gate :365 + mp4-only probe gate :252; zero-`ffprobe:` pins on 4-positional, picture, and gif rows |
| Never render fake precision (no decimal point) | ⚠️ HELD with caveat | No-decimal pin green; WR-01 floor (`~1 MB` for 1.9 MiB) is an under-statement, not fake precision — see Anti-Patterns |
| Never pre-highlight a row other than `medium` | ✓ HELD | `--default-index 1` on fixed high/medium/low order; e2e pin green |
| Never send a bare `label\tsubtext` row (leading tab mandatory) | ✓ HELD | `$'\t'` prefix :271; rows asserted as literal `\thigh\t…` in e2e |
| Subtexts contain no tabs, stay ~≤30 chars | ✓ HELD | All subtexts are constants (`CRF N · ~N MB` ≈14-24 chars, `larger than source` =18, fallbacks ≤13); filenames never enter rows |
| Helpers never placed between `transcode_video` and `copy_to_clipboard` (PR #6698 zone) | ✓ HELD | All six live in the :157-286 gap after `copy_to_clipboard` |
| No `--` terminator added to ffprobe | ✓ HELD | :164-165 and :174 match the repo's existing call sites verbatim |
| Menu.qml/MenuModel.js/omarchy-menu-select/omarchy-menu-file/transcode.py untouched | ✓ HELD | `11083223` touches exactly `bin/omarchy-transcode` + `test/shell.d/transcode-quality-test.sh`; `fbe56e4c` touches only `test/shell.d/menu-select-test.sh` (documented deviation) |
| Single atomic commit (script + test) | ✓ HELD | `git show --stat 11083223` lists exactly the two `files_modified` paths (392 insertions, 0 deletions of other files) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full stub e2e | `bash test/shell.d/transcode-quality-test.sh` | 44/44 `ok -`, 0 `not ok`, exit 0 | ✓ PASS |
| Syntax | `bash -n bin/omarchy-transcode` | exit 0 | ✓ PASS |
| Metadata lint + routing | `./test/cli` | exit 0 | ✓ PASS |
| Full shell suite | `./test/shell` | 7/240 files failed — exactly the documented environmental set (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths); transcode-quality 44/44 and menu-select 11/11 green inside | ✓ PASS |
| WR-01 floor reproduction | `awk` direct: `dur=1 kbps=15938` → `~1 MB` (mb=1.900, r=1.90); `dur=9 kbps=9000` → `~9 MB` (mb=9.656, r=9.70) | review finding independently confirmed | ⚠️ confirmed deviation (non-blocking) |
| Estimate pins | same awk on pinned inputs (60 s/1080p high+192 → ~41; 157 s → ~110/~60/~30; audio-less → ~39/~21/~10) | all match e2e-pinned values | ✓ PASS |
| Commit atomicity | `git show --stat 11083223` / `fbe56e4c` | exactly the two `files_modified` paths / only menu-select-test.sh | ✓ PASS |

### Probe Execution

No probes declared or discovered for this phase — N/A.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| QUAL-01 | 06-01 | Video transcode flow offers a quality step (high/medium/low) after format and resolution; mp4 maps to CRF tiers (x264 18/23/28, x265 20/24/28), gif to fps tiers (15/10/5) | ✓ SATISFIED | Truths 1, 5, 6, 8, 9 + artifacts; e2e pins the menu order/rows, tier CRF/fps tokens at 720p/1080p/4k, strip+re-validate, and byte-identical medium. REQUIREMENTS.md:60 maps QUAL-01→Phase 6 (marked Complete) |
| SIZE-01 | 06-01 | mp4 quality menu rows show `~N MB` estimate subtext (ffprobe duration × per-resolution/tier bitrate table + fixed 192k audio); gif rows show fps instead | ✓ SATISFIED | Truths 2, 3, 4, 5 + artifacts; e2e pins the math, sig-figs, per-row/all degrade, both fallback shapes, audio-term drop, and the gif no-probe rule. REQUIREMENTS.md:61 maps SIZE-01→Phase 6 (marked Complete). WR-01 caveat recorded under truth 2 |

No orphaned requirements: REQUIREMENTS.md maps exactly QUAL-01 and SIZE-01 to Phase 6, and both are declared in the plan's `requirements` frontmatter.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `bin/omarchy-transcode` | 238 | `printf "~%d MB", r` floor-truncates the 2-sig-fig `r` in the [1.5,10) MiB band (REVIEW WR-01, independently reproduced: 1.90→`~1`, 9.66→`~9`) | ⚠️ Warning | Deviates from the D-00h "1–2 sig figs" contract for sub-10 MiB estimates; bounded ≤~1 MB understatement, strictly conservative (never overstates), inside the feature's ±2× accuracy envelope — non-blocking for the phase goal; one-char fix `%.0f` recommended as follow-up |
| `test/shell.d/transcode-quality-test.sh` | 192-195 | Notification-ordering compare can false-pass when `notify_line` is empty (REVIEW IN-06) | ℹ️ Info | Pre-existing Phase-5 block, unchanged by this phase; a dropped notification + present ffmpeg would not be caught — noted for future hardening |
| `bin/omarchy-transcode` | 256 | `video_audio_kbps` probe runs even when the duration probe already failed (REVIEW IN-05) | ℹ️ Info | One wasted subprocess on the degraded path; conservative-192 semantics remain correct |
| `bin/omarchy-transcode` | 166 | Duration gate `^[0-9.]+$` admits malformed numerics like `1.2.3.4` (REVIEW IN-01) | ℹ️ Info | Downstream-safe (`awk -v` can't be escaped through `[0-9.]`); awk numifies the prefix — cosmetic mis-estimate on input real ffprobe never emits |
| `06-01-SUMMARY.md` | :159, :175, :227 | claims 43 assertions; file contains and runs 44 (REVIEW IN-07) | ℹ️ Info | Trivial planning-doc drift; the actual suite is greener than claimed |

No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER markers in any phase file; no stub patterns.

### Human Verification Required

The stub harness proves argv, wire format, degrade matrix, and scoping end-to-end; the remaining surface is running-UI/session behavior the dev environment cannot exercise (the dev shell loads the packaged `/usr/share/omarchy` tree). Harvested from the plan's task-3 `<human-check>` block and `06-VALIDATION.md`'s Manual-Only table:

#### 1. Quality menu rendering in the running UI

**Test:** `omarchy transcode <clip> mp4 1080p` after `omarchy-restart-shell`; observe the menu, then Enter (or `wtype -k Return`)
**Expected:** Cursor sits on `medium`; all three rows show `CRF N · ~N MB` subtexts un-elided at ~300px card width with uniform `detailRowHeight`; Enter picks medium
**Why human:** Rendered pre-highlight, elision, and row heights are running-shell properties; the stub proves argv, not pixels

#### 2. Estimate-vs-actual calibration (dogfood)

**Test:** Transcode 2–3 varied real clips through the quality menu; compare shown `~N MB` vs actual output size
**Expected:** Estimates land within ~2× of actual (CRF variance expected — inside the envelope, not exact)
**Why human:** Requires real ffprobe/ffmpeg on real media; the harness pins math against fixed durations only

#### 3. Nautilus multi-select quality prompt

**Test:** Select 2+ videos in Files → Transcode → complete the flow
**Expected:** The quality prompt appears once per file (locked behavior — verify understood, not broken)
**Why human:** Real Nautilus session; `transcode.py` invokes path-only, so the interactive chain runs per file

#### 4. Partial-positionals two-prompt chain (D-00i)

**Test:** `omarchy transcode <clip> mp4`
**Expected:** Resolution prompt fires, then the quality prompt fires
**Why human:** The single-pick stub answers every menu invocation identically, so the sequential `-z` chain cannot be driven end-to-end in the harness (plan flagged this as UAT-only)

### Gaps Summary

No gaps. All ten must-have truths verified goal-backward against the working tree with independently re-run tests (44/44 e2e, `bash -n`, `./test/cli`, `./test/shell` modulo the 7 documented environmental failures), all key links wired, all plan prohibitions held, and both requirements satisfied. One ⚠️ Warning carried forward from code review (WR-01 `estimate_label` floor-truncation below 10 MiB — independently reproduced, non-blocking, one-char `%.0f` fix available) plus info-level findings; none block goal achievement. Status is `human_needed` solely because the four running-UI/session items above cannot be proven without the live environment.

---

_Verified: 2026-09-15T22:56:52Z_
_Verifier: the agent (gsd-verifier)_
