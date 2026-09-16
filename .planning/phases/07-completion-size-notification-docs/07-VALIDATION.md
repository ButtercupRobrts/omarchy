---
phase: "7"
slug: "completion-size-notification-docs"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-16"
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash harness — `test/shell.d/*-test.sh` + `base-test.sh` `pass`/`fail`; PATH-shadowing stub binaries; per-invocation `FAKE_*` env knobs |
| **Config file** | none — `test/shell` auto-discovers `*-test.sh` |
| **Quick run command** | `bash test/shell.d/transcode-quality-test.sh` |
| **Full suite command** | `./test/shell` and `./test/cli` (or `./test/all`) |
| **Estimated runtime** | ~5 seconds (no real encodes) |

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
| TBD (T-07-size-video) | TBD | TBD | SIZE-02 | T-07-stat | video done-notification body carries real output size (`38 MB`); `stat` output regex-gated `^[0-9]+$` before `awk -v` | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ✅ (extend) | ⬜ pending |
| TBD (T-07-size-picture / -gif) | TBD | TBD | SIZE-02 | T-07-stat | picture and gif arms carry the size via the same code path | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ✅ (extend) | ⬜ pending |
| TBD (T-07-degrade) | TBD | TBD | SIZE-02 | T-07-stat, T-07-fail | stat failure / missing output degrades to plain body — never lies, never aborts under `set -euo pipefail` | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ✅ (extend) | ⬜ pending |
| TBD (T-07-failure) | TBD | TBD | SIZE-02 | T-07-fail | encode failure → zero `Transcoded` notification lines (`FAKE_ENCODE_RC` knob) | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ✅ (extend) | ⬜ pending |
| TBD (T-07-dedupe-size) | TBD | TBD | SIZE-02 | — | deduped `-2` output path still reports its own size | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ✅ (extend) | ⬜ pending |
| TBD (T-07-docs) | TBD | TBD | ROADMAP SC2 | — | `usage()`/`# omarchy:*`/`docs/`/`manual/` consistent with shipped behavior; `manual/12-screenshots-recording.md:70` gains quality step + size sentence | suite + review | `./test/cli` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Harness extension: `FAKE_OUT_BYTES` (encoder stub `truncate -s` the out path) + `FAKE_ENCODE_RC` knobs land with the first task, not as prerequisites. If the WR-01 advisory (`estimate_label` `%d`→`%.0f`) folds into this phase, add a `T-07-wr01` sub-10 MiB rounding pin.*

---

## Wave 0 Requirements

- [ ] None — `test/shell.d/transcode-quality-test.sh` exists (Phase 5/6) and this phase extends it in place; the two stub knobs land with the first task

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Done toast in the running UI shows the size legibly (glyph intact, no truncation) | SIZE-02 | Rendering is a running-UI property per `agents/skills/visual-verification.md` | Transcode a real video; confirm the completion toast body shows `N MB` |
| Estimate→actual sanity on one real clip (`~N MB` vs reported `N MB`) | SIZE-02 | Requires a real encode; the calibration loop is the feature's point | Note the `~N MB` shown in the quality menu, compare with the size in the done toast |
| `manual/12` wording reads naturally to an end user | SC2 | Doc prose — human judgment | Read the edited paragraph in `manual/12-screenshots-recording.md` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
