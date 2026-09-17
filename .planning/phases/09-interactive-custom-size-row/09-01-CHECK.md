# Plan Check — 09-01 (Interactive `Custom size…` row)

**Checked:** 2026-09-17 by gsd-plan-checker (subagent)
**Plan:** `09-01-PLAN.md` (366 lines, 3 tasks, wave 1, depends_on [])
**Verdict:** FAIL — 1 blocker, 1 warning, 3 info

Every line cite in the plan was verified against `bin/omarchy-transcode` (645 lines) and `test/shell.d/transcode-quality-test.sh` (1216 lines) at HEAD: `select_quality` :248-288 (locals :250, tier loop :260-275, menu call :277, strip :279, case :280-286), `parse_target_size` :308-324, `plan_target` :337-385 (floor `case` :364-368 lacking `*)` — IN-03 site confirmed), `transcode_video_target` :398-466, `--target` arm :481-486, menu gate :602-604, planner block :610-614, `output_path` :616, dispatch :618-633. Test-side cites all confirmed: ffmpeg stub ` -pass 2 ` counter :79, menu-select stub :136-144, `chmod +x` sweep :173, `run_transcode` :180-189 (`: >"$calls"` per-run truncation at :183), fixture :194, `cmp` idiom :200-225, Esc row :488-494, gif block :577-592, picture pin :595-603, `bogus\tjunk` pin :607-617, reject loop :872-883, refusal rows :960-991, never-probes pin :1055-1059, no-overwrite pin :1211-1216.

## Issues

```yaml
issues:
  - plan: "09-01"
    dimension: "task_completeness / verify-command sanity"
    severity: "blocker"
    required_property: "Every pinned assertion must be satisfiable — a cross-run ffmpeg-argv comparison must normalize or exclude the per-run random passdir"
    task: 1
    description: >-
      The plan's central D-00f parity pin — must_haves truth 3 (:24), Task-1 row c (:161), success criterion 2 (:357), and the <done> line (:187) — asserts
      `grep -E '^(ffmpeg |notification:)'` output is `cmp`-identical between the Custom-pick run and a `--target 25M` run. It cannot be: every two-pass run
      mints `passdir=$(mktemp -d "${TMPDIR:-/tmp}/transcode-2pass.XXXXXX")` (bin/omarchy-transcode:423) and the logged ffmpeg argv carries
      `-passlogfile "$passdir/2pass"` (:427, :439), so the two runs' `^ffmpeg ` lines always differ in the random `XXXXXX` component. `cmp -s` on raw lines
      false-REDS. The truth's own enumeration of permitted deltas ("the only call-log deltas are the menu-select:/menu-input: lines and 2 extra ffprobe:
      probes") is factually incomplete — the passdir token is a third delta the plan does not name. Corroborating evidence: every Phase-8 `--target` pin in
      the harness uses fragment greps, never a cross-run `cmp` (test:735-745, :863-866, :1070-1092); all existing `cmp` pins (:215-225, :381, :402, :453,
      :479) are on the single-pass `transcode_video` path whose argv is deterministic. `notification:` and `out=` lines ARE deterministic and cmp-able —
      only the `^ffmpeg ` lines need normalization (e.g. `sed 's|transcode-2pass\.[^/ ]*|transcode-2pass.X|'` before cmp) or a projection that strips the
      `-passlogfile` pair.
    fix_hint: "In rows b/c, sed-normalize the `transcode-2pass.XXXXXX` segment (or drop `-passlogfile <arg>`) on both greps before `cmp -s`, and update truth 3 / criterion 2 / <done> to name the normalization; alternatively split the pin into `cmp` on `notification:` lines plus fragment greps on the deterministic ffmpeg fields."
  - plan: "09-01"
    dimension: "key_links_planned / verification derivation"
    severity: "warning"
    required_property: "Each assertion row must name the data source it actually reads — the Custom run's saved log, not whichever run most recently truncated $calls"
    task: 1
    description: >-
      `run_transcode` truncates `$calls` per invocation (`: >"$calls"` at test:183). Row a says "keep this run's log for rows a–d" (:159), but row b then
      runs `run_transcode … --target 25M` (:160) which truncates it; row c's literal command `grep -E '^(ffmpeg |notification:)' "$calls" >parity-menu`
      (:161) would then compare the CLI run against itself — a tautological parity assert — and row d's sentinel-leak sweep (:162) would scan the wrong
      run. The plan hedges ("re-run the Custom pick if the log was truncated between rows") so the property is stated, but the written command sequence is
      ambiguous enough to produce a false-green `cmp` if followed literally.
    fix_hint: "Make the save explicit: `cp \"$calls\" \"$TMPDIR/calls-custom\"` at the end of row a, then grep/cmp `$TMPDIR/calls-custom` in rows c–d (or re-run the Custom pick and use its fresh log)."
  - plan: "09-01"
    dimension: "nyquist_compliance"
    severity: "info"
    required_property: "VALIDATION.md's per-task map should reflect the plan's task list"
    description: "09-VALIDATION.md's Per-Task Verification Map lists only 09-01-01 while the plan has 3 tasks; all three verify via the same automated commands (`bash test/shell.d/transcode-quality-test.sh`, `bash -n`, `./test/cli`, `./test/shell`), so coverage is unaffected — coarser map only."
    fix_hint: "Optionally add rows for 09-01-02/03 pointing at the same automated commands when validate-phase next runs."
  - plan: "09-01"
    dimension: "requirement_coverage"
    severity: "info"
    required_property: "Edge coverage suggested by 09-RESEARCH §5c should be present or consciously omitted"
    description: "RESEARCH §5c lists a 'probe failure parity' row (FAKE_INPUT=25M with FAKE_DURATION unset → planner refuses `Cannot determine duration`, proving a Custom pick degrades identically to CLI when menu probes fail); the plan's ~11 rows omit it. Not a ROADMAP criterion; all 5 success criteria remain pinned."
    fix_hint: "Optionally add the row; the path also exercises the qualitative-subtext branch with the sentinel present."
  - plan: "09-01"
    dimension: "scope_sanity"
    severity: "info"
    required_property: "Estimate confidence should be flagged when uncalibrated"
    description: "`estimate.tokens: 55000` with `confidence: low` (<3 phases with actuals — figure not calibrated for this repo). Within thresholds regardless (3 tasks, 2 files; 08-01 shipped at 70000). gsd-tools estimate-check unavailable in this environment; manual assessment only."
    fix_hint: "None — informational."
```

## Key correctness questions — answers

1. **Sentinel row after tier loop / `--default-index 1` → medium:** YES — append between `done` (:275) and `selection=` (:277), mp4-gated; sentinel lands at index 3, medium's pre-highlight at index 1 preserved.
2. **Sentinel branch placement / `target:<bytes>`:** YES — after the strip (:279), before the tier `case` (:280); `printf 'target:%s' "$bytes"` minted inside the branch, never re-enters the whitelist.
3. **`main()` unwrap clears `quality`:** YES — `quality=""` inside the :602-604 gate, correctly flagged load-bearing (otherwise `target:<n>` reaches `output_path` :616 and the tier case).
4. **Stub in same commit (Pitfall 11):** YES — Task 1 writes the stub; Task 3 makes one atomic commit of both `files_modified` paths.
5. **Three-state semantics:** YES — unset `FAKE_INPUT` → exit 1 (Esc/tripwire); set-empty → exit 0 empty stdout (empty submit, faithful to the real binary writing `\n` so `-s` is true at `bin/omarchy-menu-input:54`); set → exit 0 + text.
6. **Re-prompt bound / D-02 hint / D-01 refusals:** YES — `for attempt in 1 2` (visible bound, one re-prompt max); `prompt="Invalid size — e.g. 25M"` (U+2014) assigned only after a failed parse; the loop wraps `parse_target_size` only, never `plan_target`.
7. **Pinned test values vs reality:** PARTIAL — 4 ffprobe lines on the happy path verified (2 menu probes :253-258 → `video_duration`/`video_audio_kbps` at :165/:175, + 2 planner probes :350/:352); `3233k` @25M/60s/audio-192 verified arithmetically (26214400·8/60/1000·0.98−192 → %d → 3233; consistent with existing pin :863); `~4 MB` floor refusal verified ((400+192)·60·125/1048576 → `4 MB`; matches :966); `in-1080p-25M.mp4` verified (`numfmt --to=iec 26214400` = `25M`; :865/:1198 confirm). **BUT** the `cmp`-identical `^ffmpeg` claim is unsatisfiable — see blocker.
8. **IN-01/IN-03 fold-ins:** YES — both DECIDED IN in Flagged assumptions; IN-03 `*)` arm is purely additive (audit correctly expects exactly one removed line per file: :250 locals + `for bad in` line); truth 10 carves out the IN-03 exception to the byte-identical claim.
9. **Frontmatter/threat model/D-citations:** YES — `requirements: [MENU-02]` matches ROADMAP; threat model T-09-01..05 with ASVS level 1 covers the sentinel→argv boundary; D-00a..f + D-01 + D-02 all cited in tasks and source-coverage audit; discretion items documented; deferred ideas (prefill, refusal re-prompt, gif row) correctly absent.

## Dimension notes

- Requirement coverage: MENU-02 → tasks 1+2; all 5 ROADMAP success criteria trace to assertion rows. COVERED.
- Task completeness: all 3 tasks carry files/action/verify/done/acceptance_criteria; `type="tracer"` matches the 08-01 schema precedent. PASS modulo the blocker.
- Dependencies: single plan, `depends_on: []`, wave 1 — acyclic trivially; Phase-8 precondition asserts machinery exists at HEAD (verified present).
- Context compliance: every locked decision honored; no deferred-idea leakage; no scope reduction.
- Nyquist: every task decided by automated checks that can fail; the human-check is explicitly `gating="false"` (UAT-recorded, matching VALIDATION.md's manual-only dogfood item).
- AGENTS.md compliance: `#!/bin/bash` stubs, `[[ ]]`/`(( ))`, no `local` on captures, atomic single-concern commit, `./test/shell` + `./test/cli` sweep.
- Research resolution: `## Open Questions` contains no unresolved items ("None blocking").
- Verify-format sanity: no `^`-anchored package-list greps, no error-swallowing `|| echo "0"` comparisons; the `grep -c` count pins have measured provenance (2+2 probe split verified in source).

## Files changed by this check

- Created `.planning/phases/09-interactive-custom-size-row/09-01-CHECK.md` (this report).
