---
phase: "08"
slug: "non-interactive-target-size-targeting"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-17"
---

# Phase 08 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| CLI argv → `main()` arg loop | untrusted free-text size string and paths cross the parse boundary | Free-text size → integer bytes only |
| media file → ffprobe output → `awk -v` | crafted/unreadable media yields attacker-controlled duration strings crossing into arithmetic | Duration float → awk gates (`d <= 0 → exit 1`) |
| script → `TMPDIR` passdir / output dir | passlog and retry-temp files cross into shared-writable directories | `mktemp -d` unique dir per run |
| script → ffmpeg argv | derived `-b:v`/`-passlogfile` values cross into subprocess argv | Regex+numfmt-gated integers and mktemp paths only |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-08-01 | Tampering | `--target` free text → `target_bytes`/`target_token` → filename + ffmpeg argv | medium | mitigate | `parse_target_size` regex `^[0-9]+(\.[0-9]+)?([kKmMgG][bB]?)?$` + `numfmt --from=iec` belt; only integer bytes and the canonical `numfmt --to=iec` token propagate | closed |
| T-08-02 | DoS | degenerate values / failed probes → `-nan`/negative/absurd `-b:v` or division fault | medium | mitigate | `(( bytes > 0 ))` post-numfmt; `d <= 0 → exit 1` inside awk; negative `video_kbps` rides floor loop to honest refusal | closed |
| T-08-03 | Tampering | stale/predictable passlog location → corruption of next run or artifacts in output dir | medium | mitigate | `mktemp -d "${TMPDIR:-/tmp}/transcode-2pass.XXXXXX"` per run + path-baked EXIT trap `rm -rf` + explicit rm; never output dir or `$output` as prefix | closed |
| T-08-04 | Tampering | retry path clobbering good output or looping | low | mitigate | exactly one retry; encodes to `$passdir/retry.mp4`, `mv -f` only on success; failed retry preserves the overshot output | closed |
| T-08-05 | Tampering | user's input file overwritten or deleted | high | mitigate | `$output` always derived `stem-<res>-<token>.<fmt>`, deduped via `[[ -e \|\| -L ]]`; `mv` targets `$output` only; no path writes to `$input` | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

**Closure evidence (L1):** T-08-01 — `bin/omarchy-transcode:308-324`; live numfmt checks (`0.000001M`→2B floor-refused, huge→rc 2 rejected), 82/82 e2e incl. reject matrix. T-08-02 — `:357-360` awk `d<=0→exit 1`; reviewer reproduced all pinned budget values, no `-nan`/negative `-b:v` path exists. T-08-03 — `:423-424` mktemp + path-baked EXIT trap (fixes local-unbound trap bug caught in execution) + `:465` explicit rm; stub proves zero `*2pass*` leftovers on all three outcomes. T-08-04 — `:450-461` exactly-once retry, `mv -f` success-gated. T-08-05 — UAT refusal + dedupe verified live; verifier confirmed no `$input` write path.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-08-01 | T-08-04 | Retry `mv -f` TOCTOU — a file materializing between dedupe and `mv` is silently replaced; `mv` never prompts (slightly worse than v1.1's ffmpeg-prompt degradation class) | plan (deferred-items IN-06) | 2026-09-17 |
| R-08-02 | T-08-02 | `--target` + positional-menu gif with unset resolution wastes one resolution prompt before refusing — ordering locked by the check site | plan (deferred-items IN-05) | 2026-09-17 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-17 | 5 | 5 | 0 | Devin (gsd-secure-phase, L1 — ASVS 1 short-circuit: register authored at plan time, threats_open 0) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-17
