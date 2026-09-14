---
phase: "03"
slug: "scale-aware-monitor-position-adjustment"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-14"
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash harness (`test/shell.d/base-test.sh` assertions + stub `hyprctl` on `PATH`) |
| **Config file** | none — `test/shell.d/` convention |
| **Quick run command** | `bash test/shell.d/monitor-scaling-test.sh` |
| **Full suite command** | `./test/cli && ./test/shell` (note: `./test/shell` has ~7-8 pre-existing environmental failures — compare against base, not zero) |
| **Estimated runtime** | ~15 seconds focused; ~60 seconds full |

---

## Sampling Rate

- **After every task commit:** Run `bash test/shell.d/monitor-scaling-test.sh`
- **After every plan wave:** Run `bash test/shell.d/monitor-scaling-test.sh && bash test/shell.d/monitor-clamshell-scale-test.sh && ./test/cli`
- **Before `/gsd-verify-work`:** Full suite must be green (or match the known-environmental failure set)
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | SCALE-08 | — | Atomic scale+position eval; adjacency preserved; no new overlap/gap | unit + e2e | `bash test/shell.d/monitor-scaling-test.sh` | ✅ | ⬜ pending |
| 03-01-02 | 01 | 1 | SCALE-09 | — | `position =` rewritten in place via descending-offset edits; literal-only; `auto*` skipped | e2e | `bash test/shell.d/monitor-scaling-test.sh` | ✅ | ⬜ pending |
| 03-01-03 | 01 | 1 | SCALE-10 | — | `omarchy_gdk_scale` = round(max(all monitor scales)) | e2e | `bash test/shell.d/monitor-scaling-test.sh` | ✅ | ⬜ pending |
| 03-01-04 | 01 | 1 | SCALE-08/09/10 | — | Full regression sweep incl. transform replay + audit-log fields | e2e | `bash test/shell.d/monitor-scaling-test.sh && ./test/cli` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky — task IDs are seeded; planner may re-split but must keep per-requirement coverage.*

---

## Wave 0 Requirements

- [ ] `bin/omarchy-hyprland-monitor-scaling` — dispatch guard `[[ ${BASH_SOURCE[0]} == "$0" ]]` so tests can `source` and call `recompute_monitor_position` directly (2-line refactor, part of task 1)
- [ ] `test/shell.d/monitor-scaling-test.sh` — stub growth: `OMARCHY_TEST_MONITORS_JSON` raw pass-through + `OMARCHY_TEST_MONITORS_JSON_AFTER_EVAL` post-eval knob (part of test tasks)

*Framework and harness already exist — no installs needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Samsung rescale keeps layout + bar intact | SCALE-08 | Requires live compositor + physical 2-monitor layout | `omarchy hyprland monitor scaling 1.5 HDMI-A-1` → no overlap warning, cursor crosses, `hyprctl reload` stays clean |
| Panel pill rescale preserves adjacency | SCALE-08 | Visual UAT of the full path (panel → CLI → eval → persist) | Click a different scale pill on the Samsung bar's panel → Samsung stays adjacent, no dead clicks, no translucent bar |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
