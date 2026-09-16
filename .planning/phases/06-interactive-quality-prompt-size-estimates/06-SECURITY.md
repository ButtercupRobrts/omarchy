---
phase: "06"
slug: "interactive-quality-prompt-size-estimates"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-16"
---

# Phase 06 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| ffprobe/stat → `awk -v` / `[[ =~ ]]` | External tool output enters shell arithmetic/string ops | Duration string, source byte count (untrusted process output) |
| `omarchy-menu-select` return → `quality` → `output_path` + ffmpeg argv | User/menu subprocess output flows into filename construction and encoder argv | `label⇥subtext` string (potentially malformed) |
| probe failure under `set -euo pipefail` on detached/keybind launch | Non-interactive invocation has no human to notice a silent abort | Exit status / partial prompt chain |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-06-01 | Tampering | ffprobe/stat output → `awk -v`/`[[ =~ ]]` in `video_duration`/`estimate_label` | high | mitigate | Probe output treated as data: `=~ ^[0-9.]+$` on duration (`bin/omarchy-transcode:166`) and `=~ ^[0-9]+$` on `stat` bytes (:255) BEFORE any `awk -v`; `N/A`/junk → `duration=""` → qualitative fallback; no `eval`, no `(( ))` on probe output | closed |
| T-06-02 | Tampering | menu return `label⇥subtext` → `quality` → `output_path` suffix + ffmpeg argv | medium | mitigate | `select_quality` strips at first tab (`${selection%%$'\t'*}`, :276) AND re-runs the `high\|medium\|low` case on the stripped value (:278-283) — foreign label fails with `Invalid video quality` inside the helper, before the notification boundary | closed |
| T-06-03 | DoS | probe hiccup under `set -euo pipefail` on a detached/keybind launch → silent abort mid-flow | high | mitigate | Every probe guarded: `ffprobe … 2>/dev/null \|\| true` (:165), `if streams=$(…)` (:173), `\|\| duration=""` (:253), `stat … \|\| true` (:254); failure degrades to all-qualitative rows — never dies between prompts; menu-select empty-pick exit-1 is the only sanctioned abort | closed |
| T-06-04 | Tampering | tab-bearing subtext or filename → option field splitting | low | accept | Menu options are three fixed literal strings built in `select_quality`; subtexts are constants with no tabs; filenames never enter menu options | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-06-01 | T-06-04 | Row fields are compile-time literals; a tab can only arrive via a crafted menu return, which T-06-02's re-validation already rejects | planner (D-04 empty-glyph decision context) | 2026-09-16 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-16 | 4 | 4 | 0 | verify-work (L1 grep-depth, short-circuit: plan-authored register, threats_open=0, ASVS L1) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
