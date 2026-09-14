---
phase: 01-per-monitor-scale-persistence-in-the-scaling-cli
verified: 2026-09-14T10:42:27Z
status: passed
score: 8/8 must-haves verified
covered_files:
  - .planning/phases/01-per-monitor-scale-persistence-in-the-scaling-cli/01-01-PLAN.md
  - .planning/phases/01-per-monitor-scale-persistence-in-the-scaling-cli/01-01-SUMMARY.md
  - bin/omarchy-hyprland-monitor-scaling
  - test/shell.d/monitor-scaling-test.sh
covered_digest: "v1:sha256:197ea87f1dffd75ed0db7c4c80689f340c1038464b55a62783eb063bdd751be3"
behavior_unverified: 0
---

# Phase 1: Per-monitor scale persistence in the scaling CLI Verification Report

**Phase Goal:** `bin/omarchy-hyprland-monitor-scaling` persists a scale change to the target monitor's own `hl.monitor()` line in `~/.config/hypr/monitors.lua` and keeps the monitor's configured position when applying live via `hyprctl eval`
**Verified:** 2026-09-14T10:42:27Z
**Status:** passed

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Scale change rewrites `scale` on the target monitor's own `hl.monitor()` entry (name- or `desc:`-keyed, single- or multi-line, inserting when absent) and survives reload | ✓ VERIFIED | `persist_monitor_scale` + awk rewriter at `bin/omarchy-hyprland-monitor-scaling:124-401`; test cases at `monitor-scaling-test.sh:259-317` (in-place, variable-pinning, multi-line, insert-when-absent, `desc:`); independent probe rewrote a `desc:`-keyed multi-line rule, inserted `, scale = 3` before the closing brace |
| 2 | Unlisted monitor gets an appended single-line name-keyed rule carrying live mode/position; `omarchy_monitor_scale` and `output = ""` catch-all stay byte-identical | ✓ VERIFIED | Append path at `:379-386`; test cases at `:340-356`; probe confirmed catch-all + variable untouched |
| 3 | Live `hyprctl eval` emits `position = "<liveX>x<liveY>"` from `hyprctl monitors -j`, never `position = "auto"` | ✓ VERIFIED | Eval at `:111` uses `${x}x${y}` from `.x`/`.y` (`:89-90`); `grep -n 'position = "auto"'` → no output; assertions at `:156-157, :261-262, :388` |
| 4 | `monitors.lua.bak.<timestamp>` backup precedes every write; symlinked config stays a symlink | ✓ VERIFIED | `cp -- "$monitor_lua" "$monitor_lua.bak.$(date +%s)"` at `:140`; writes via `cat "$tmp" >"$monitor_lua"` (`:377`) and `sed -i --follow-symlinks` (`:398-401`); tests at `:359-380` |
| 5 | Optional `[monitor]` arg: defaults to focused, steps the target's live scale, rejects unknown/unsafe names with no eval and no write | ✓ VERIFIED | `target_monitor` param at `:77`, `jq --arg` selector at `:79-83`, name guard at `:98-101`, `$# > 2` arity guard at `:463-466`, `up`/`down` targeted resolution at `:480-495`; tests at `:384-442` |
| 6 | Bare invocation prints exactly the focused monitor's scale (monitor-state contract unchanged) | ✓ VERIFIED | `""` dispatch arm at `:469-475` still calls `focused_monitor_scale \| normalize_scale`; test at `:446-448`; `monitor-state-test.sh` exits 0 |
| 7 | `local omarchy_gdk_scale` and/or `hl.env("GDK_SCALE", "N")` update to nearest integer on every persist path | ✓ VERIFIED | `sed -i --follow-symlinks -E` covering both shipped forms at `:398-401`, runs after both the rewrite (`cat >`) and append paths; tests at `:191, :201, :208` |
| 8 | `monitor-scaling-test.sh`, `monitor-state-test.sh`, `monitor-clamshell-scale-test.sh`, `monitor-output-name-test.sh`, `./test/cli` all pass | ✓ VERIFIED | Re-run during verification: 31/5/25/8 `ok -` lines respectively, `./test/cli` exit 0 |

**Score:** 8/8 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `bin/omarchy-hyprland-monitor-scaling` | `[monitor]` arg, `persist_monitor_scale` awk rewriter, backup + symlink-safe writes, live x/y eval, deleted sed branches, updated metadata | ✓ EXISTS + SUBSTANTIVE | 509 lines; diff 41b7ea3d..HEAD +354; both old sed branches gone; `persist_monitor_scale` at :124-402; awk rewriter at :161-370; no `position = "auto"`, no `omarchy_monitor_scale` anywhere in the script |
| `test/shell.d/monitor-scaling-test.sh` | Grown stub (x/y/description/make/model/serial, env-gated second monitor), re-pointed assertions, 10 fixture writers, ~16 new cases | ✓ EXISTS + SUBSTANTIVE | 448 lines; +337 in diff; 10 `write_*_config()` fixture writers; 31 `pass` cases; stub carries all required fields and `OMARCHY_TEST_EXTERNAL_MONITOR` gate |

**Artifacts:** 2/2 verified

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `set_scale` | `persist_monitor_scale` | 13-arg call at `:114-115` | ✓ WIRED | Includes description/make/model/serial for `desc:` matching |
| `persist_monitor_scale` | awk rewriter | `env OMARCHY_TARGET_*` / `ENVIRON` at `:155-371` | ✓ WIRED | Identity via environment, never `-v`; exit codes 0/3/other drive cat-through/append/warn at `:373-393` |
| `set_scale` | live `hyprctl eval` | `position = "${x}x${y}"` at `:111` | ✓ WIRED | x/y read from `hyprctl monitors -j` at `:89-90` |
| dispatch | `set_scale`/`jq` selector | `up`/`down`/numeric arms pass `"${2:-}"` at `:479-508` | ✓ WIRED | `>2` args rejected at `:463-466`; bare call preserved at `:469-475` |
| appended rule format | clamshell parser contract | single-line name-keyed `hl.monitor({...})` at `:385-386` | ✓ WIRED | `monitor-clamshell-scale-test.sh` exits 0 |

**Wiring:** 5/5 connections verified

## Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| SCALE-01: persist on the monitor's own `hl.monitor()` line, survives reload | ✓ SATISFIED | - |
| SCALE-02: live apply preserves configured position, never `position = "auto"` | ✓ SATISFIED | - |
| SCALE-03: stock `omarchy_monitor_scale` variable / literal catch-all configs still persist | ✓ SATISFIED | - (append path verified; variable/catch-all byte-identical) |
| SCALE-04: realistic shapes — multi-line, `desc:`, missing scale key | ✓ SATISFIED | - (all covered by tests + independent probe) |

**Coverage:** 4/4 requirements satisfied. REQUIREMENTS.md marks SCALE-01..04 complete — accurate.

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| bin/omarchy-hyprland-monitor-scaling | 304 | First-match `scale` key ignores brace depth (W1) | ⚠️ Warning | Nested-table `scale` rewritten instead of top-level; requires a nested `scale` key inside `hl.monitor()` — not a shipped/typical shape |
| bin/omarchy-hyprland-monitor-scaling | 238 | Levelled long comments `--[==[` untracked (W2) | ⚠️ Warning | Rule inside `--[==[ ]==]` is scanned as live code; rare legal Lua form |
| bin/omarchy-hyprland-monitor-scaling | 307 | Value terminator stops at first `,` (W3) | ⚠️ Warning | `scale = math.max(1, 1.5)` → invalid Lua; backup covers recovery |

**Anti-patterns:** 3 found (0 blockers, 3 warnings — all from 01-REVIEW.md, confirmed consistent with the code)

### Judgment on review warnings W1–W3

All three are residual edge cases, not contradictions of the must_haves:

- The must_haves and plan spec cover name-/`desc:`-keyed rules, single-/multi-line, missing-scale insertion — every required shape is handled and tested. The plan's own spec ("rewrite `scale` (key preceded by `[{,;[:space:]]`)") describes first-match semantics; W1 is faithful-to-spec behavior on an input shape the plan did not require.
- W2 requires `--[=*[` levelled comments; the plan specified `--` and `--[[ ]]` only. Shipped `config/hypr/monitors.lua` contains neither levelled comments nor nested tables nor expression scale values.
- W3 requires a non-literal scale expression containing a top-level comma; stock configs use literals or the `omarchy_monitor_scale` variable. The timestamped backup bounds the blast radius.

None trigger on shipped or typical `monitors.lua` shapes; none block the phase goal. Appropriate as follow-up hardening (see review's suggested follow-ups), not phase gaps.

## Human Verification Required

None — all verifiable items checked programmatically. (Live `hyprctl`/`hyprctl reload` behavior on real hardware is inherently environment-dependent; the stubbed suite exercises every code path.)

## Gaps Summary

**No gaps found.** Phase goal achieved. Ready to proceed.

### Independent sanity probes (beyond the test suite)

- `bash -n bin/omarchy-hyprland-monitor-scaling` → exit 0
- `bash test/shell.d/monitor-scaling-test.sh` → 31 `ok -`, 0 `not ok -`, exit 0
- `grep 'position = "auto"'` on the script → no matches (absent entirely)
- `grep 'omarchy_monitor_scale'` on the script → no matches (absent entirely, including comments)
- Missing `monitors.lua` → stderr warning, exit 0, file never created, live eval still applied
- Unreadable `monitors.lua` → stderr warning, exit 1, no write
- `desc:`-keyed multi-line rule with no `scale` key → `, scale = 3` inserted in place before `}`; catch-all, variable byte-identical; `omarchy_gdk_scale` updated to 3; timestamped backup created

### Summary cross-reference

01-01-SUMMARY.md claims verified against code: 13-arg `persist_monitor_scale` (plan's 9 + 4 identity fields), 0/3/other awk exit contract, `local status=0` + `|| status=$?` capture, no literal `'` in the awk program, trailing-newline guard before append (`:382-384`), reworded `omarchy:summary`. Claims "30 passing cases" — actual is 31 `ok -` lines (harmless undercount). Commits `eb68cc30`/`5a4f071b`/`54fec018` confirmed in `git log`; task-4 sweep produced no file changes as stated. `git status --porcelain` shows only pre-existing `M bin/omarchy-capture-text` and untracked `.planning/` files — consistent with the summary.

## Verification Metadata

**Verification approach:** Goal-backward (derived from phase goal + plan must_haves)
**Must-haves source:** 01-01-PLAN.md `must_haves` section
**Automated checks:** 9 passed (4 test suites + cli lint + bash -n + 3 greps + 3 manual probes), 0 failed
**Human checks required:** 0
**Note:** `./test/shell` aggregate reports 7 pre-existing environment failures (needs sibling `omarchy-pkgs` checkout, live compositor, snapper) — documented in 01-01-SUMMARY.md as failing identically at base commit `41b7ea3d`; every monitor-related suite passes.
**Total verification time:** ~10 min

---
*Verified: 2026-09-14T10:42:27Z*
*Verifier: the agent (subagent)*
