---
phase: "8"
slug: "non-interactive-target-size-targeting"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-16"
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test harness (`test/shell.d/*-test.sh` sourced assertions + `test/cli` metadata lint) |
| **Config file** | `test/shell.d/base-test.sh` (shared root-path discovery + assertions) |
| **Quick run command** | `bash test/shell.d/transcode-quality-test.sh` |
| **Full suite command** | `./test/shell` (plus `./test/cli` and `bash -n bin/omarchy-transcode`) |
| **Estimated runtime** | ~15 seconds (stubbed ffmpeg/ffprobe — no real encodes) |

---

## Sampling Rate

- **After every task commit:** Run `bash test/shell.d/transcode-quality-test.sh`
- **After every plan wave:** Run `./test/shell` and `./test/cli`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | SIZE-10, SIZE-13, SIZE-14, SIZE-15, SAFE-02 | T-8-01 / — | `--target` parses free-text sizes to integer bytes; refuses bad input, gif/picture/quality-conflict, sub-floor budgets, and probe failure on stderr before any menu or notification; no `-nan`/zero/negative `-b:v` ever reaches ffmpeg argv | integration (stub harness) | `bash test/shell.d/transcode-quality-test.sh` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. The pass-aware ffmpeg stub, notification-stub `-p` arm, and `TMPDIR` export in `run_transcode` land inside `test/shell.d/transcode-quality-test.sh` in the same atomic commit as the implementation — no separate Wave 0 scaffolding task.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real ffmpeg accepts the derived two-pass argv and output lands under target | SIZE-10 | Stubs prove argv shape, not encoder acceptance | Optional dogfood: `omarchy transcode <real-clip> mp4 1080p --target 10M` → lands under 10M, playable, both toasts name the effective resolution. Non-blocking. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
