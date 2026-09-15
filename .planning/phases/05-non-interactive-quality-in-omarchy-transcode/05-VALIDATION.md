---
phase: "05"
slug: "non-interactive-quality-in-omarchy-transcode"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-15"
---

# Phase 05 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test harness (`test/shell.d/*-test.sh` + `base-test.sh` assertions; stub binaries via `PATH` shadowing) |
| **Config file** | none — `test/shell` auto-discovers `*-test.sh` |
| **Quick run command** | `bash test/shell.d/transcode-quality-test.sh` |
| **Full suite command** | `./test/all` (or `./test/shell` + `./test/cli`) |
| **Estimated runtime** | ~5 seconds (no real encodes — ffmpeg/magick stubbed) |

---

## Sampling Rate

- **After every task commit:** Run `bash test/shell.d/transcode-quality-test.sh` and `bash -n bin/omarchy-transcode`
- **After every plan wave:** Run `./test/shell` and `./test/cli`
- **Before `/gsd-verify-work`:** Full suite must be green (excluding the 7 documented pre-existing environmental failures)
- **Max feedback latency:** ~15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | QUAL-02, QUAL-03, SAFE-01 | T-05-01 | Quality arg validated before any notification; dedupe resolves path before "Transcoding…"; `[[ -e \|\| -L ]]` blocks symlink write-through | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 1 | QUAL-02, QUAL-03, SAFE-01 | — | Full assertion matrix green incl. byte-identical medium, dedupe chains, picture rejection pre-notification | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` | ✅ | ⬜ pending |
| 05-01-03 | 01 | 1 | QUAL-02 | — | usage()/metadata reflect `[quality]`; `./test/cli` metadata lint stays green | lint+docs | `./test/cli && bash -n bin/omarchy-transcode` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/shell.d/transcode-quality-test.sh` — new file (name locked to avoid add/add collision with upstream PR #6698's `transcode-test.sh`); stub bins: `file` (mandatory — empty fixtures report `inode/x-empty`), `ffmpeg`, `magick`, `wl-copy`, `omarchy-notification-send`, plus `omarchy-menu-file`/`omarchy-menu-select` tripwires that exit 1

*Harness pattern already proven in `menu-plugin-test.sh` / `menu-select-test.sh` / `monitor-scaling-test.sh` — no framework install needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Detached launch never hits ffmpeg's overwrite prompt on a re-run | SAFE-01 | "No tty, no hang" is a property of the real launch environment (`Util.execDetached`); the stub proves the path is collision-free but not the launch | Transcode the same video at the same settings twice via the actual keybind/menu trigger — second run produces `-2` output with no prompt |
| Real-encode smoke | QUAL-02 | Stubbing proves argv, not encoder acceptance | `omarchy transcode <clip> mp4 720p high` produces a playable file (optional, low cost) |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (the test file itself)
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter (set by validate-phase audit)

**Approval:** pending
