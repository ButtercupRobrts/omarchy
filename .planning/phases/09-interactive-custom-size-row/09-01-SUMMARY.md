---
phase: 09-interactive-custom-size-row
plan: 01
subsystem: ui
tags: [bash, omarchy-transcode, omarchy-menu-input, omarchy-menu-select, ffmpeg, sentinel-row, dmenu]

requires:
  - phase: 08-non-interactive-target-size-targeting
    provides: parse_target_size, plan_target, transcode_video_target, the --target flag arm, and the pass-aware stub harness this phase's menu path reuses verbatim
provides:
  - mp4-gated `Custom size…` sentinel row appended last in select_quality with mandatory subtext and --default-index 1 retained
  - post-strip/pre-case sentinel branch minting `target:<bytes>` on select_quality's return channel
  - prompt_target_size() helper owning the bounded 2-attempt re-prompt budget and the D-02 `Invalid size — e.g. 25M` hint
  - main() `target:` unwrap inside the menu gate producing byte-identical argv/toasts vs `--target`
  - omarchy-menu-input stub (FAKE_INPUT/FAKE_INPUT$n per-invocation knobs, unset = exit-1 tripwire)
  - IN-01 ("" in the --target reject loop) and IN-03 (plan_target floor-case `*)` arm) closures
affects: [transcode, menu, nautilus-transcode]

actuals:
  tokens: 3984
  tasks: 3
  commits: 1
  plan_head_before: f0e8909fde93b5efc37f36aa1d0d9a0b249fe092

tech-stack:
  added: []
  patterns:
    - "Sentinel-prefix return channel: menu pick mints `target:<bytes>` past the strip but before the tier whitelist; main() unwraps inside the menu gate so CLI runs can never see one"
    - "Bounded re-prompt loop: `for attempt in 1 2` inside prompt_target_size — exit 1 = Esc/cancel, exit-0-with-empty = empty submit riding through parse_target_size"
    - "Per-invocation stub knobs: FAKE_INPUT$n dispatched off the just-logged menu-input: line count (the ffmpeg stub's pass-2 queue convention)"

key-files:
  created: []
  modified:
    - bin/omarchy-transcode
    - test/shell.d/transcode-quality-test.sh

key-decisions:
  - "Sentinel row label `Custom size…` (U+2026) + subtext `Enter a size like 25M` single-sourced in the select_quality :250 locals so row text and the byte-exact [[ == ]] match cannot drift"
  - "Sentinel branch extends the chokepoint (post-strip, pre-case) rather than bypassing it; `|| return` mirrors the omarchy-menu-select cancel chain"
  - "Empty submits ride through parse_target_size (one validator for both entry points); the ^[0-9]+$ guard after the unwrap makes the mint contract explicit at the sentinel→main boundary"
  - "IN-01 and IN-03 folded into the same atomic commit — the helpers are now genuinely multi-caller"

patterns-established:
  - "menu-input stub contract: log `menu-input: %s` before the decision, unset knob = exit 1 (Esc + tripwire), set-empty = exit-0 empty submit, %s never %q so literal-tab grep -F pins hold"
  - "Passdir-normalized parity pin: cmp `^(ffmpeg |notification:)` lines between a menu-picked Custom run and a --target run after `sed 's|transcode-2pass\\.[^/ ]*|transcode-2pass.X|'`"

requirements-completed: [MENU-02]

coverage:
  - id: D1
    description: "mp4 Select quality menu offers Custom size… last with a subtext, medium pre-highlighted; gif menus never contain it; pictures never reach the menu"
    requirement: MENU-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh — 'the mp4 menu offers Custom size… last with a subtext and medium pre-highlighted'; gif block Custom-absence pin; picture pin unchanged"
        status: pass
    human_judgment: false
  - id: D2
    description: "Custom pick fires omarchy-menu-input 'Target size (e.g. 25M)'; a 25M answer produces ffmpeg argv and notification lines cmp-identical to --target 25M (passdir-normalized), out=in-1080p-25M.mp4, 4 ffprobe probes"
    requirement: MENU-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh — 'a Custom size pick encodes byte-identically to --target 25M' + 'a --target 25M run never prompts and probes exactly twice'"
        status: pass
    human_judgment: false
  - id: D3
    description: "Empty submit and unparseable input each re-prompt exactly once with 'Invalid size — e.g. 25M'; exhaustion and Esc at either prompt cancel nonzero pre-notification; ≤2 menu-input: lines"
    requirement: MENU-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh — empty-submit, unparseable, exhaustion, Esc-at-re-prompt, Esc-at-first-prompt rows"
        status: pass
    human_judgment: false
  - id: D4
    description: "Sentinel label and target: mint never reach the tier case, ffmpeg argv, or an out= line; bogus\\tjunk foreign-label pin stays green; below-floor answer refuses byte-identically to --target 4M with exactly 1 menu-input: line"
    requirement: MENU-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh — sentinel-leak sweep row, 'a below-floor Custom answer refuses byte-identically to --target 4M', foreign-label pin"
        status: pass
    human_judgment: false
  - id: D5
    description: "Dogfood the Custom size… row in the running UI (prompt-as-placeholder render, Enter submits, Esc cancels, hinted re-prompt, uniform row height)"
    requirement: MENU-02
    verification: []
    human_judgment: true
    rationale: "Menu rendering and Esc/Enter UX are QML-level behavior in the running shell; the stub harness proves the contract but not the visual row height/highlight — the dev shell loads the packaged /usr/share/omarchy tree so the agent cannot exercise the real menu"

# Metrics
duration: 16min
completed: 2026-09-17
status: complete
---

# Phase 9 Plan 01: Interactive `Custom size…` row Summary

**mp4 quality menu gains a `Custom size…` sentinel row → `omarchy-menu-input` free-text prompt → `target:<bytes>` through select_quality's return → main() unwrap into the Phase-8 `--target` pipeline — ffmpeg argv and toasts cmp-identical to a CLI run, one atomic commit.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-09-17T12:08:52Z
- **Completed:** 2026-09-17T12:24:38Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- `select_quality` appends an mp4-gated `Custom size…` row LAST (subtext `Enter a size like 25M` mandatory for uniform row heights; `--default-index 1` keeps medium pre-highlighted), label/subtext single-sourced via `$custom_label`/`$custom_subtext` so the byte-exact match cannot drift.
- Post-strip/pre-`case` sentinel branch mints `printf 'target:%s'` — the whitelist keeps rejecting every other foreign label (`bogus\tjunk` pin untouched).
- New `prompt_target_size()` helper after `parse_target_size`: `for attempt in 1 2`, Esc cancels at either prompt, empty/unparseable buys exactly one re-prompt carrying `Invalid size — e.g. 25M` (D-02), planner refusals never re-prompt (D-01).
- `main()` unwraps `target:<bytes>` inside the menu gate (`target_bytes`/`target_token`/`quality=""` + `^[0-9]+$` guard) — downstream is literally the `--target` path; a CLI run can never see a sentinel it did not mint.
- `omarchy-menu-input` stub ships in the same commit (Pitfall 11): `menu-input:` logged before the decision, `FAKE_INPUT`/`FAKE_INPUT$n` per-invocation knobs counted off the log, unset = exit-1 Esc/tripwire.
- IN-01 (`""` in the `--target` reject loop → exit 2) and IN-03 (`plan_target` floor-case `*)` arm → `Invalid video resolution`) closed.

## Task Commits

The plan mandated a single atomic commit for the whole phase (script + harness are the reviewable unit):

1. **Tasks 1–3 (tracer slice + edge/cancel/refusal rows + sweep/audit):** `1fd54ced` (feat) — `bin/omarchy-transcode` +43/-1, `test/shell.d/transcode-quality-test.sh` +204/-1

## Files Created/Modified

- `bin/omarchy-transcode` — sentinel row append, sentinel branch, `prompt_target_size()` helper, `target:` unwrap inside the menu gate, IN-03 `*)` floor-case arm; the only removed line is the old `:250` locals declaration
- `test/shell.d/transcode-quality-test.sh` — `omarchy-menu-input` stub, `--- Custom size… ---` section (~10 assertion rows), gif Custom-absence pin, IN-01 `""` token; the only removed line is the old `for bad in` loop

## Decisions Made

- Exercised the discretion items exactly as the plan flagged: subtext `Enter a size like 25M`, loop shape `for attempt in 1 2`, branch placement post-strip/pre-`case`, stub knobs `FAKE_INPUT`/`FAKE_INPUT$n`.
- Verified the `[[ $format == "mp4" ]] && rows+=(…)` idiom is safe under `set -e` (the failing `[[ ]]` is a non-final `&&` member — gif menu path confirmed by the green gif rows).

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- `./test/shell` reported 8 failed files: the 7 known environmental set (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths) plus `bar-widget-contract-test.sh`. The latter is an unrelated teardown flake — its only assertion passed (`ok - bar widget contracts pass`); the file was counted failed because its `rm -rf $TMPDIR` trap raced an asynchronously-created `home/.codex` directory (`rm: cannot remove … Directory not empty`). It passes 3/3 standalone and is untouched by this diff.

## UAT Checklist (recorded, not executed — end-of-phase human verification)

(a) `omarchy transcode <real-clip> mp4 1080p` → `Select quality` shows `Custom size…` last with its subtext at uniform row height, medium still pre-highlighted → pick it → type `25M` → output lands with the `target ≤25M` toast and `-25M` filename.
(b) Esc at the input prompt cancels silently before any toast.
(c) Empty submit re-prompts showing `Invalid size — e.g. 25M`.
(d) A below-floor answer (e.g. `4M` on a 60 s clip) refuses naming the achievable minimum with no second prompt.
(e) The gif menu shows no Custom row.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 9 plan 01 complete; MENU-02 satisfied by stub-harness proofs. The dogfood checklist above is the only manual-only item (QML untouched).
- `./test/shell` carries 7 known environmental failures + the `bar-widget-contract` teardown flake noted above — none attributable to this phase.

## Self-Check: PASSED

- `bash -n bin/omarchy-transcode` → 0; `bash test/shell.d/transcode-quality-test.sh` → 90 `ok -`, 0 `not ok -`; `./test/cli` → 0, 0 `not ok -`; `./test/shell` → only the environmental set (+flake noted).
- `git show --stat HEAD` (feature commit `1fd54ced`) lists exactly `bin/omarchy-transcode` and `test/shell.d/transcode-quality-test.sh`.
- Additive-diff audit: one removed line per file; `bin/omarchy-menu-input`, `bin/omarchy-menu-select`, `shell/`, `docs/`, `manual/` diffs empty.
- `git log --oneline --grep="09-01"` → `1fd54ced` present.

---
*Phase: 09-interactive-custom-size-row*
*Completed: 2026-09-17*
