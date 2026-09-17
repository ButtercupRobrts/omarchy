---
phase: "09"
slug: "interactive-custom-size-row"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-17"
---

# Phase 09 — Validation Strategy

> Every Phase-9 success criterion maps to stub-harness assertions; the whole phase is automatable.

## Test Environment

| Layer | Command | Purpose |
|-------|---------|---------|
| Syntax | `bash -n bin/omarchy-transcode` | parse check |
| Focused e2e | `bash test/shell.d/transcode-quality-test.sh` | full assertion matrix incl. new Custom-size rows (82 → ~92) |
| Metadata lint | `./test/cli` | `args=`/`examples=` unchanged-shape verification |
| Full suite | `./test/shell` | regression sweep — **7 known environmental failures** (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths); do not chase |

## Success-Criterion → Proof Map (from 09-RESEARCH.md Validation Architecture)

| # | Success criterion | Automated proof |
|---|-------------------|------------------|
| 1 | mp4 menu shows `Custom size…` 4th w/ subtext; gif never | `grep -F $'\tCustom size…\t<subtext>'` on the `menu-select:` line + `--default-index 1` retained; `! grep -F 'Custom' "$calls"` on gif run |
| 2 | Row → `omarchy-menu-input`; valid answer ≡ `--target` argv | `cmp` the `^ffmpeg`/`notification:` lines between Custom-pick run and `--target 25M` run; `menu-input:` line logged |
| 3 | Empty/unparseable re-prompt once then cancel; Esc pre-notification | `FAKE_INPUT`/`FAKE_INPUT2` rows: 2 `menu-input:` lines (2nd carries `Invalid size`), run completes; Esc row exits nonzero, no `notification:`/`ffmpeg` |
| 4 | Sentinel never reaches tier case/ffmpeg | `! 'Invalid video quality'` on stderr; no `ffmpeg`/`out=` line contains `Custom`/`target:`; foreign-label pin unchanged |
| 5 | `omarchy-menu-input` stubbed same commit (no hang) | Suite green IS the proof — every Custom row exercises the stub |

**Requirement traceability:** MENU-02 ← SC 1–5.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | MENU-02 | T-9-0x | Sentinel row + `prompt_target_size` + `target:` unwrap + input stub + parity rows — one atomic commit | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

## Wave 0

None — existing harness covers everything; the `omarchy-menu-input` stub lands inside the same atomic commit as the feature (Pitfall 11 forbids a follow-up).

## Manual-Only Items

| Item | Why manual | Command |
|------|-----------|---------|
| Dogfood Custom-size pick in the running UI | prompt-as-placeholder render + Esc/submit semantics are QML-level (untouched, but worth a spot-check) | `omarchy transcode <clip> mp4 1080p` → pick `Custom size…` → type `25M` |

## Known Limitations (from research)

- Custom pick pays 2 extra `ffprobe` estimate probes vs CLI — inherent to showing tier estimates beside the sentinel; milliseconds, not a bug.
- `prompt_target_size` stderr invisible on menu-launched runs — D-02's hint prompt is the real error surface.
- Esc-on-input is two-stage when text present (inherited QML UX, unchanged).

## Nyquist Checklist

- [x] Every success criterion has an automated proof
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter (set by validate-phase audit)

**Approval:** pending
