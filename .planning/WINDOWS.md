---
schema_version: 1
open_count: 2
waived_count: 0
fixed_count: 0
total_count: 2
last_updated: 2026-09-15T22:25:26.710Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 5 | unrun-verify | .planning/phases/05-non-interactive-quality-in-omarchy-transcode/05-01-SUMMARY.md |  | Detached-launch + real-encode UAT deferred (non-gating): keybind re-run produces -2 output with no overwrite prompt; optional real-encode smoke | open |  | 2026-09-15T14:58:01.974Z |  |
| 2 | 06 | unrun-verify | .planning/phases/06-interactive-quality-prompt-size-estimates/06-01-SUMMARY.md |  | Running-UI + dogfood UAT deferred (non-gating): quality menu renders cursor on medium with un-elided subtexts and uniform row heights; ~N MB estimates within ~2x of real output on 2-3 clips; Nautilus multi-select prompts quality per video; omarchy transcode <clip> mp4 prompts resolution then quality | open |  | 2026-09-15T22:25:26.710Z |  |

````json
[
  {
    "id": 1,
    "kind": "unrun-verify",
    "phase": "5",
    "file": ".planning/phases/05-non-interactive-quality-in-omarchy-transcode/05-01-SUMMARY.md",
    "line": null,
    "description": "Detached-launch + real-encode UAT deferred (non-gating): keybind re-run produces -2 output with no overwrite prompt; optional real-encode smoke",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-15T14:58:01.974Z",
    "resolved_at": null
  },
  {
    "id": 2,
    "kind": "unrun-verify",
    "phase": "06",
    "file": ".planning/phases/06-interactive-quality-prompt-size-estimates/06-01-SUMMARY.md",
    "line": null,
    "description": "Running-UI + dogfood UAT deferred (non-gating): quality menu renders cursor on medium with un-elided subtexts and uniform row heights; ~N MB estimates within ~2x of real output on 2-3 clips; Nautilus multi-select prompts quality per video; omarchy transcode <clip> mp4 prompts resolution then quality",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-15T22:25:26.710Z",
    "resolved_at": null
  }
]
````
