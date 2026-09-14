---
status: fixed
date: 2026-09-14
fix_scope: critical_warning
commit: 19df93db
---

# Phase 2 Review Fix: Warning only (8 Info items left as-is)

## Finding → Fix

**W — `scaleMonitor` header could render `NAME · x` while `ownScale` is empty** (`shell/plugins/panels/monitor/Panel.qml`, was :775-776).

The header `Text` bound `visible` only to `root.ownScreenName !== ""`, so while `displays`/`monitorScale` were still empty (first `stateProc` poll window, or persistently when line 6 of `omarchy-monitor-state` output is empty — no focused monitor / failing scaling CLI) it painted e.g. `eDP-1 · x`.

Fix: gated `visible` on both conditions as the review suggested — `visible: root.ownScreenName !== "" && root.ownScale !== ""` — so the header never prints a bare `· x`. Single-line edit; no other binding touched. The 8 Info findings were out of scope and are unchanged.

## Test update

`test/shell.d/monitor-test.sh:161-164` pinned the exact `visible:` binding string (`visible: root.ownScreenName !== ""`), which would false-fail on the new expression. Updated the assertion to `visible: root.ownScreenName !== "" && root.ownScale !== ""` and reworded its label to "shows only when the own screen and its scale are known". No other assertion referenced the old binding.

## Verification

- `bash test/shell.d/monitor-test.sh` → all 43 `ok -`, exit 0.
- `bash test/shell.d/monitor-state-test.sh` → all `ok -`, exit 0 (sibling suite, confirms no collateral breakage).
- Committed atomically as `fix(monitor-panel): hide scale header while own scale is unknown` (19df93db) — only `Panel.qml` + `monitor-test.sh` staged; the pre-existing `M bin/omarchy-capture-text` was left unstaged.
