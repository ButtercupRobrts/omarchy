---
phase: 09-interactive-custom-size-row
verified: 2026-09-17T12:54:54Z
status: human_needed
score: 10/10 must-haves verified
covered_files:
  - .planning/REQUIREMENTS.md
  - .planning/ROADMAP.md
  - .planning/phases/09-interactive-custom-size-row/09-01-PLAN.md
  - .planning/phases/09-interactive-custom-size-row/09-01-SUMMARY.md
  - .planning/phases/09-interactive-custom-size-row/09-CONTEXT.md
  - .planning/phases/09-interactive-custom-size-row/09-REVIEW.md
  - .planning/phases/09-interactive-custom-size-row/09-VALIDATION.md
  - .planning/phases/09-interactive-custom-size-row/deferred-items.md
  - bin/omarchy-transcode
  - test/shell.d/transcode-quality-test.sh
covered_digest: "v1:sha256:5f1332e8b2772325e5465ba81e2dd956dfe6e5c445f7e3df6ac12045ee10c10c"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Dogfood the Custom row in the running UI: `omarchy transcode <real-clip> mp4 1080p` → `Select quality` → confirm `Custom size…` renders as the fourth, last row WITH its subtext (`Enter a size like 25M`) at the same row height as the tiers, and medium is still pre-highlighted → pick it → the input card opens with prompt `Target size (e.g. 25M)` → type `25M` → Enter"
    expected: "The run encodes exactly like `--target 25M`: one toast updates pass 1/2 → pass 2/2, done toast reports the stat-measured size, output lands as `<stem>-<res>-25M.mp4`"
    why_human: "The stub proves the menu argv (row text, order, `--default-index 1`), the prompt arg, and argv parity — not that the real Menu.qml input mode renders the prompt as placeholder, that row heights stay uniform with the subtext present, or that the real pick-list returns the row verbatim; the dev shell loads the packaged /usr/share/omarchy tree, not this checkout (per SUMMARY D5)"
  - test: "In the same dogfood: press Esc at the input prompt; then re-pick the row and submit an empty answer; then submit garbage (`bogus`)"
    expected: "Esc cancels silently with zero notifications; an empty submit and `bogus` each re-prompt exactly once showing `Invalid size — e.g. 25M`; a second Esc or second bad answer cancels the run"
    why_human: "The stub pins the exit-1/exit-0-empty contract and the 2-prompt bound, but Esc key handling (including the inherited two-stage Esc-when-text-present quirk noted in VALIDATION limitations) and the hint's visual presentation are QML-level behavior no stub exercises"
  - test: "Still in the dogfood (optional): `omarchy transcode <clip> gif 720p` and a `4M`-class below-floor answer on mp4"
    expected: "The gif `Select quality` menu shows no `Custom` row; a parseable-below-floor answer refuses naming the achievable minimum (`~N MB`) with no second prompt"
    why_human: "Both are stub-pinned (forged-gif pin :617-628, byte-identical refusal :1400-1424); the residual is only that the real binary renders and dismisses identically — a spot-check, not new behavior"
---

# Phase 9: Interactive `Custom size…` row Verification Report

**Phase Goal:** The mp4 `Select quality` menu gains a `Custom size…` row that opens `omarchy-menu-input`, feeds the typed answer through the same `parse_target_size` → `plan_target` path as `--target`, re-prompts once on empty or unparseable input, and cancels cleanly on Esc — with zero QML and zero `omarchy-menu-select` changes
**Verified:** 2026-09-17T12:54:54Z
**Status:** human_needed — all 10 must-haves verified against disk with an independently re-run suite (93/93) plus a manual stub harness I built myself; the real-menu dogfood genuinely requires the running UI
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1 | An interactive mp4 run logs a `menu-select:` argv carrying four `\t<label>\t<subtext>` rows — three tiers plus `Custom size…` appended LAST with subtext `Enter a size like 25M` — retaining `--default-index 1`; gif never contains `Custom`; pictures never reach the quality menu (SC1, D-00a/D-00b) | ✓ VERIFIED | Locals `custom_label="Custom size…"`/`custom_subtext`/`bytes` single-sourced `bin/omarchy-transcode:251`; mp4-gated last-position append `[[ $format == "mp4" ]] && rows+=(…)` :280 (after tier loop `done` :276, before menu call :282 which retains `-- --default-index 1`). e2e green: literal pin `grep -F $'\tCustom size…\tEnter a size like 25M -- --default-index 1'` test:1262-1265; gif-absence pin :602-604; picture pin :631-639. Independently reproduced in my own stub env: `menu-select: Select quality \thigh\tCRF 18 · ~41 MB \tmedium\tCRF 23 · ~23 MB \tlow\tCRF 28 · ~11 MB \tCustom size…\tEnter a size like 25M -- --default-index 1` |
| 2 | Picking the sentinel logs `menu-input: Target size (e.g. 25M)` — `omarchy-menu-input` is the prompt surface, prompt arg verbatim (SC2, D-00c) | ✓ VERIFIED | `prompt_target_size` :344-355: `local prompt="Target size (e.g. 25M)"` :345, `answer=$(omarchy-menu-input "$prompt") || return 1` :347. e2e green: `grep -Fx 'menu-input: Target size (e.g. 25M)'` test:1294-1295 + exactly-1 count :1292. Manual run confirmed the same log line |
| 3 | A valid Custom answer (`FAKE_INPUT=25M`) produces `^ffmpeg`/`notification:` lines `cmp`-identical to `--target 25M` after `sed 's|transcode-2pass\.[^/ ]*|transcode-2pass.X|'` normalizes the per-run passdir; only deltas are `menu-select:`/`menu-input:` lines and 2 extra `ffprobe:` estimate probes (4 vs 2) (SC2, D-00f) | ✓ VERIFIED | Normalized `cmp -s` pin test:1270-1299 (CLI baseline :1271-1278 asserts 2 probes + zero menu lines; Custom side :1284-1298 asserts cmp parity, `out=$TMPDIR/in-1080p-25M.mp4`, 4 probes). Manual run: built my own stub set, ran both invocations, `cmp` on normalized greps → `PARITY: identical` |
| 4 | `target:<bytes>` is minted only inside the post-strip/pre-`case` branch; the sentinel label never reaches the tier whitelist, `output_path`, an `out=` line, or ffmpeg argv; `bogus\tjunk` pin stays green (SC4, D-00b) | ✓ VERIFIED | Strip :284 → sentinel branch :286-290 (`printf 'target:%s' "$bytes"; return`) → tier `case` :292-298 with `*)` rejection. e2e green: no `Custom`/`target:` on any `ffmpeg`/`out=` line test:1303-1310, `Invalid video quality` absent from stderr :1311-1313, tier-pick-never-prompts :1315-1319, `bogus\tjunk` pin :643-653 green |
| 5 | The `target:` unwrap lives inside the `[[ $type == "video" && -z $quality && -z $target_bytes ]]` menu gate and sets `target_bytes`/`target_token`/`quality=""` — a CLI `--target` run can never see a sentinel it did not mint (SC4, D-00b/D-00f) | ✓ VERIFIED | Gate :634, unwrap :639-645: `target_bytes="${quality#target:}"`, `^[0-9]+$` guard :641-642, `target_token=$(numfmt --to=iec …)` :643, `quality=""` :644 — downstream :652-678 is literally the Phase-8 path. CLI runs carry `-n $target_bytes` so skip the gate. Manual run 2 confirmed a `--target` run logs zero menu lines |
| 6 | Empty submit (exit-0-with-empty) and unparseable answers each re-prompt exactly once — second call carries `Invalid size — e.g. 25M` — never more than 2 `menu-input:` lines (SC3, D-00d/D-02) | ✓ VERIFIED | `for attempt in 1 2` :346 is the visible bound; failed parse → `prompt="Invalid size — e.g. 25M"` :352; loop falls through to `return 1` :354. e2e green: empty-submit row test:1324-1334 (2 calls, hint on 2nd, run encodes), unparseable :1337-1349, exhaustion :1353-1364 (exactly 2 calls). Manual run 5: `bogus`→`25M` logged `Target size (e.g. 25M)` then `Invalid size — e.g. 25M`, exit 0 |
| 7 | Every cancel path — Esc on select menu, Esc on either input prompt, re-prompt exhaustion — exits nonzero before the start notification with no `notification:`/`^ffmpeg` lines, ≤2 `menu-input:` lines (SC3, D-00d) | ✓ VERIFIED | `answer=$(omarchy-menu-input …) || return 1` :347 propagates Esc through `bytes=$(prompt_target_size) || return` :287 up `select_quality`'s `|| return` chain at :282 — aborts before the start toast :670. e2e green: Esc-at-re-prompt :1367-1381, Esc-at-first-prompt :1386-1398 (1 input line, 2 probes, planner never ran), exhaustion :1353-1364, select-menu Esc :505-514. Manual run 4: Esc at first prompt → exit 1, 1 `menu-input:`, 0 `notification:`/`ffmpeg`, 2 `ffprobe:` |
| 8 | A parseable-below-floor answer (`FAKE_INPUT=4M`) aborts exactly like `--target 4M` — stderr byte-identical naming `~4 MB`; exactly 1 `menu-input:` line proves the re-prompt budget never wraps `plan_target` (SC3, D-01) | ✓ VERIFIED | `plan_target` refusal `*)` arm :405-412 prints `Cannot fit under … smallest achievable is ~$min_label`; the re-prompt loop :346-353 wraps only `parse_target_size`. e2e green: stderr `cmp -s` between `--target 4M` baseline and the Custom run test:1400-1424, `-eq 1` input count :1419, pre-notification :1421 |
| 9 | The `omarchy-menu-input` stub ships in the same commit — `menu-input:` logged before the decision, `FAKE_INPUT`/`FAKE_INPUT$n` knobs counted off `grep -c '^menu-input:'`, unset knob exits 1 as the Esc/tripwire state (SC5, D-00e) | ✓ VERIFIED | Stub test:156-164 inside commit `1fd54ced` (same commit as the feature): `printf 'menu-input: %s\n'` :158 precedes knob dispatch :159-161 (`var=FAKE_INPUT`, `(( n > 1 )) && var="FAKE_INPUT$n"`), `[[ -z ${!var+x} ]] && exit 1` :162, `%s` not `%q`. Suite green IS the hang-free proof — 93/93 with no `done_file` spin-wait |
| 10 | Zero new CLI surface — `usage()`, `# omarchy:args=`/`# omarchy:examples=`, `bin/omarchy-menu-select`, `bin/omarchy-menu-input`, and all QML byte-identical; sole permitted Phase-8-block deviation is the IN-03 `*)` floor arm (SC5, additive-diff constraint) | ✓ VERIFIED | `git diff f0e8909f..HEAD -- bin/omarchy-menu-input bin/omarchy-menu-select shell/ docs/ manual/` empty; feature commit `1fd54ced` removed exactly one line in `bin/omarchy-transcode` (old :250 locals); WR-01 fix `79928688` touched only the new branch + doc comment. IN-03 `*) echo "Invalid video resolution: $res" >&2; return 1 ;;` present at :399. `usage()` :13-21 and metadata :6-7 verified present and unmodified; `./test/cli` green (112 ok) |

**Score:** 10/10 truths verified (0 present, behavior-unverified)

**ROADMAP success criteria:** SC1 → truths 1; SC2 → truths 2-3; SC3 → truths 6-8; SC4 → truths 4-5; SC5 → truths 9-10. All five covered by verified truths.

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `bin/omarchy-transcode` | mp4-gated `Custom size…` sentinel row appended last in `select_quality`, post-strip sentinel branch minting `target:<bytes>`, bounded `prompt_target_size`, `target:` unwrap inside `main()`'s menu gate, IN-03 `*)` floor arm | ✓ VERIFIED | Doc comment updated for the third return shape :243-248 (IN-01 closed); locals :251; append :280; branch :286-290 format-gated per WR-01 fix `79928688`; `prompt_target_size` :344-355 after `parse_target_size` :320-336; IN-03 arm :399; unwrap :639-645 inside gate :634. `bash -n` exit 0 |
| `test/shell.d/transcode-quality-test.sh` | `omarchy-menu-input` stub (`menu-input:` log, `FAKE_INPUT`/`FAKE_INPUT$n`, unset=exit-1 tripwire) + ~10 assertion rows (row shape/position, prompt text, CLI parity, re-prompt budget, cancel paths, floor refusal, gif absence, sentinel non-leakage) + IN-01 `""` token | ✓ VERIFIED | Stub :146-164 with three-state doc block; `--- Custom size… ---` section :1247-1424 (10 pass rows); forged-gif pin :617-628 (WR-01 closure); gif Custom-absence :602-604; IN-01 `for bad in abc -5M 0 25.5.2M ""` :908. 93 `ok`, 0 `not ok` on independent re-run |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `select_quality` row builder | sentinel branch | `omarchy-menu-select` returns `label\tsubtext`; `${selection%%$'\t'*}` strip :284 hands the label back; `[[ $format == "mp4" && $selection == "$custom_label" ]]` :286 matches byte-exact before the tier `case` — label/subtext single-sourced in :251 locals so row and match cannot drift | ✓ WIRED | Manual run logged the row arg verbatim and the pick resolved to `target:<bytes>`; forged-gif run fell through to `*)` → `Invalid video quality: Custom size…` (the format gate added by `79928688` is load-bearing — verified live) |
| sentinel branch | `prompt_target_size()` → `parse_target_size()` | `bytes=$(prompt_target_size) || return` :287; helper's `for attempt in 1 2` owns the whole re-prompt budget; `parse_target_size` output is the only thing printed :348-350 | ✓ WIRED | Manual run 5 showed garbage→hinted re-prompt→accept; exit-1 (Esc) and exit-0-empty stay distinct per the `[[ -s $selection_file ]]` contract the stub mirrors |
| `select_quality` return channel | `main()` → `plan_target` → `transcode_video_target` | `[[ $quality == target:* ]]` :639 unwraps `target_bytes`/`target_token`/`quality=""` :640-644 inside the menu gate; planner :652-656, `output_path` :658, dispatch :660-678 are byte-identical to `--target` | ✓ WIRED | `cmp` parity pin green in suite AND reproduced in my own stub env — argv and toast text identical modulo the normalized passdir |
| test stub `omarchy-menu-input` | `FAKE_INPUT`/`FAKE_INPUT$n` knobs | `printf 'menu-input: %s\n' "$*"` :158 before `n=$(grep -c '^menu-input:' "$CALLS")` :159 — the ffmpeg stub's pass-2 queue convention; unset knob `exit 1` :162 | ✓ WIRED | All re-prompt rows exercise `FAKE_INPUT2`; a hypothetical 3rd call hits unset `FAKE_INPUT3` → exit 1 while `-eq 2` counts still catch it — no false-green vector |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `bin/omarchy-transcode` | menu pick → `selection` → `bytes` (prompt_target_size → parse_target_size) → `target:<bytes>` → `target_bytes`/`target_token` → `plan_target` → `resolution`/`video_kbps` → ffmpeg argv/`out=`/toasts | real `omarchy-menu-input` answer validated to integer bytes | Yes — every downstream value derives from the typed answer through the identical Phase-8 gates (regex + numfmt + positive); manual run recorded the full chain | ✓ FLOWING |

### Prohibitions (negative checks — all empirically verified)

| Prohibition | Status | Evidence |
| ----------- | ------ | -------- |
| Sentinel label never reaches the tier `case`, ffmpeg argv, an `out=` line, or a filename | ✓ HELD | Branch mints+returns :286-290 before `case` :292; `quality=""` :644 before `output_path` :658; sweep pins :1303-1313 + forged-gif :617-628 green; manual forged-gif run died `Invalid video quality: Custom size…` |
| Row never appended ungated, subtext-less, or out of last position | ✓ HELD | `[[ $format == "mp4" ]]` gate :280 after tier loop; `custom_subtext` always in the row; pin asserts `\tCustom size…\tEnter a size like 25M -- --default-index 1` (last arg before ` -- `) :1262-1265 |
| No `local x=$(…)` capture masking | ✓ HELD | `grep 'local .*=\$('` over the new regions (:250-252, :280, :286-290, :344-355, :399, :639-645) empty; captures ride `if` conditions (:348) or `||` chains (:287, :347) |
| Never conflate exit-0-empty with exit-1, never re-prompt beyond `for 1 2`, never wrap `plan_target` in the retry | ✓ HELD | `for attempt in 1 2` :346 (the `while :` at :394 is Phase-8's pre-existing floor loop, not the re-prompt); empty rides `parse_target_size`; loop wraps the parser only — refusal rows pin 1 `menu-input:` line :1419 |
| No stray stdout inside `select_quality`/`prompt_target_size` (both run in `$( )`) | ✓ HELD | Only `printf 'target:%s'` :288 and `printf '%s' "$bytes"` :349 write the channel; `parse_target_size` failures go to stderr (documented invisible-in-menu); `omarchy-menu-input` output captured into `answer` :347 |
| `…` written as one U+2026 char, single-sourced via `$custom_label` | ✓ HELD | `grep -c $'Custom size…'` on :251 = 1; the literal appears nowhere else in the script (row, match, and comment all use the variable) |
| `usage()`/`args=`/`examples=`, `bin/omarchy-menu-select`, `bin/omarchy-menu-input`, all QML untouched | ✓ HELD | `git diff f0e8909f..HEAD` on those paths empty; `git diff` grep for usage/metadata lines empty; `./test/cli` metadata lint green |
| Stub ships in the same commit; no `%q` logging | ✓ HELD | Stub inside `1fd54ced` with the feature; `%s` at :158 |
| Never copy the CLI's 2-probe pin onto the interactive path | ✓ HELD | Custom run asserts `-eq 4` :1296-1298; CLI twin asserts `-eq 2` :1274 — both green |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full stub e2e | `bash test/shell.d/transcode-quality-test.sh` | 93/93 `ok -`, zero `not ok`, exit 0 (ran twice) | ✓ PASS |
| Syntax | `bash -n bin/omarchy-transcode` | exit 0 | ✓ PASS |
| Metadata lint + routing | `./test/cli` | exit 0, 112 `ok`, 0 `not ok` | ✓ PASS |
| Manual spot-run (own stub env): Custom pick 25M vs `--target 25M` | minimal stub harness, `cmp` on normalized `^(ffmpeg \|notification:)` greps | `PARITY: identical`; menu-select argv shows row last with subtext + `--default-index 1`; `menu-input: Target size (e.g. 25M)` logged once | ✓ PASS |
| Manual spot-run: forged gif sentinel | `FAKE_PICK=$'Custom size…\t…'` on gif run | exit 1 `Invalid video quality: Custom size…`; 0 `menu-input:` lines; gif menu argv has no Custom row | ✓ PASS |
| Manual spot-run: Esc at first input | `FAKE_INPUT` unset | exit 1; 1 `menu-input:` line; 0 `notification:`/`ffmpeg`; 2 `ffprobe:` (menu estimates only, planner never ran) | ✓ PASS |
| Manual spot-run: garbage → hint → accept | `FAKE_INPUT=bogus FAKE_INPUT2=25M` | exit 0; prompts `Target size (e.g. 25M)` then `Invalid size — e.g. 25M`; stderr carried `Invalid target size: bogus` | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| MENU-02 | 09-01 | mp4 quality menu gains `Custom size…` row → `omarchy-menu-input` free-text → same size parser → same target path; empty/unparseable re-prompts once then cancels (empty submit is exit-0-with-empty, not a cancel) | ✓ SATISFIED (pending human UI sign-off) | All 5 ROADMAP success criteria verified via truths 1-10; every clause of the requirement text has a green e2e pin. Bookkeeping note: REQUIREMENTS.md traceability still shows `Pending` — the flip is the post-verification/UAT workflow step, consistent with the `human_needed` status |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `bin/omarchy-transcode` | :455 | `XXXXXX` in `mktemp -d` template | ℹ️ Info (false positive) | mktemp placeholder syntax, not a debt marker |

No TBD/FIXME/TODO/HACK markers, no empty implementations, no hardcoded-empty stubs in the phase diff.

### Notes (non-blocking)

- **Two code commits, not one:** the plan mandated a single atomic commit; the feature landed as `1fd54ced` and the WR-01 review fix as `79928688` (also atomic, single-concern). SUMMARY `actuals.commits: 1` predates the review fix — documentation drift only.
- **IN-02 deferred:** mint-guard `return 1` vs `--target`'s `return 2` for the same `Invalid target size` class — unreachable by construction (the mint only produces `^[0-9]+$`); recorded in `deferred-items.md` as cosmetic.
- **WR-01 verified closed:** sentinel branch is format-gated `:286`; forged-gif pin `:617-628` green; independently reproduced in my own stub env.
- **IN-01 closed twice over:** doc comment now describes the `target:<bytes>` return (`:243-248`) AND the `""` token joined the `--target` reject loop (`:908`).
- `./test/shell` environmental failures (7 known + bar-widget teardown flake) documented in SUMMARY — untouched by this diff, not re-run (per spot-check constraints the focused suite + `./test/cli` suffice).

### Human Verification Required

#### 1. Custom-size dogfood in the running UI

**Test:** `omarchy transcode <real-clip> mp4 1080p` → `Select quality` → confirm `Custom size…` renders fourth/last with its subtext at uniform row height, medium still pre-highlighted → pick it → input card shows `Target size (e.g. 25M)` → type `25M` → Enter
**Expected:** One toast updates pass 1/2 → pass 2/2; done toast reports stat-measured size; output lands as `<stem>-<res>-25M.mp4`
**Why human:** The stub proves menu argv, prompt arg, and argv parity — not QML rendering (row height, placeholder text, pre-highlight) or that the real binaries behave identically; the dev shell loads the packaged tree, not this checkout

#### 2. Cancel and re-prompt UX in the running UI

**Test:** Esc at the input prompt; re-pick → empty submit; re-pick → type `bogus`
**Expected:** Esc cancels silently before any toast; empty submit and `bogus` each re-prompt once showing `Invalid size — e.g. 25M`; second Esc/bad answer cancels
**Why human:** Esc key handling (incl. the inherited two-stage Esc-with-text quirk) and the hint's visual presentation are QML-level; the stub only proves the exit-code contract

#### 3. Optional spot-checks in the same session

**Test:** `omarchy transcode <clip> gif 720p` menu; a `4M`-class below-floor answer on mp4
**Expected:** No `Custom` row in the gif menu; below-floor answer refuses naming `~N MB` achievable minimum with no second prompt
**Why human:** Stub-pinned already — residual is only real-binary render/dismiss fidelity

---

## VERIFICATION COMPLETE

**Score: 10/10 must-haves verified** — status `human_needed` solely for the running-UI dogfood; every automatable claim is green against disk and independently reproduced.

_Verified: 2026-09-17T12:54:54Z_
_Verifier: the agent (gsd-verifier)_
