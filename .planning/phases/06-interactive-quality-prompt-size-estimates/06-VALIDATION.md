---
phase: "06"
slug: "interactive-quality-prompt-size-estimates"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-15"
---

# Phase 06 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test harness (`test/shell.d/*-test.sh` + `base-test.sh` assertions; stub binaries via `PATH` shadowing) |
| **Config file** | none — `test/shell` auto-discovers `*-test.sh` |
| **Quick run command** | `bash test/shell.d/transcode-quality-test.sh` |
| **Full suite command** | `./test/all` (or `./test/shell` + `./test/cli`) |
| **Estimated runtime** | ~5 seconds (no real encodes — ffmpeg/magick/ffprobe stubbed) |

---

## Sampling Rate

- **After every task commit:** Run `bash test/shell.d/transcode-quality-test.sh` and `bash -n bin/omarchy-transcode`
- **After every plan wave:** Run `./test/shell` and `./test/cli`
- **Before `/gsd-verify-work`:** Full suite must be green (excluding the 7 documented pre-existing environmental failures — they reproduce at base commit `41b7ea3d`; don't chase them)
- **Max feedback latency:** ~15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 06-01-TBD | 01 | 1 | QUAL-01 | T-06-01 | ffprobe output regex-validated before awk/`(( ))`; menu pick re-validated `high\|medium\|low` after tab-strip | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ✅ | ⬜ pending |
| 06-01-TBD | 01 | 1 | SIZE-01 | T-06-01 | `~N MB` at 1–2 sig figs; `larger than source` degrade; N/A→all-qualitative fallback; no probe on positional path | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Planner replaces TBD rows with real task IDs; harness upgrade (dual-mode menu-select stub, arg-dispatched ffprobe stub, `truncate -s` fixtures) lands with the first task.*

---

## Wave 0 Requirements

- [ ] None — `test/shell.d/transcode-quality-test.sh` exists (Phase 5) and this phase extends it in place; no new framework, fixtures, or files required

*Harness pattern already proven in `menu-plugin-test.sh` / `monitor-scaling-test.sh` — no framework install needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Quality menu opens with cursor on `medium`, subtexts un-elided at ~300px card width, uniform `detailRowHeight` | QUAL-01/SIZE-01 | Rendering/elision is a running-UI property per `agents/skills/visual-verification.md`; stubs prove argv, not pixels | Open the quality menu in the running shell; verify cursor on `medium`, no trailing `…`, all rows same height |
| Estimate-vs-actual calibration on 2–3 real clips | SIZE-01 | Real encodes only; ±2× CRF variance is expected — check estimates land inside it | Transcode 3 varied clips; compare shown `~N MB` vs actual output size |
| Nautilus multi-select prompts quality per video file | QUAL-01 | Real Nautilus session; locked behavior — verify understood, not broken | Multi-select 2+ videos in Files → Transcode; confirm quality prompt appears per file |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
