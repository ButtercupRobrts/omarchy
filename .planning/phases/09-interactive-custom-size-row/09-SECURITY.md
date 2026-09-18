---
phase: "09"
slug: "interactive-custom-size-row"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-18"
---

# Phase 09 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| menu pick → `select_quality` | untrusted label\tsubtext pair crosses the sentinel-acceptance boundary | Exact-match `Custom size…` label on mp4 only → `target:<bytes>` sentinel |
| input card text → `parse_target_size` | free-text answer crosses into byte math | Reuses T-08-01's regex + numfmt + positive gates verbatim |
| `target:<bytes>` sentinel → `main()` unwrap | sentinel string crosses into the `--target` path | `^[0-9]+$` guard; `quality=""` so downstream sees the CLI shape |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-09-01 | Tampering | sentinel label `Custom size…` → strip → tier `case`/`output_path`/ffmpeg | high | mitigate | branch sits between the strip and the whitelist case; single-sourced `$custom_label`; `target:` minted only inside the branch; **WR-01 review fix added `[[ $format == "mp4" ]]` gating so a forged gif pick can never mint mp4 bytes into a `.gif` name** | closed |
| T-09-02 | Tampering | `quality="target:<bytes>"` leaking past the unwrap into suffix/tier case | high | mitigate | unwrap inside the `[[ -z $quality && -z $target_bytes ]]` menu gate sets `quality=""`; `^[0-9]+$` guard rejects malformed mints; CLI runs skip the gate entirely | closed |
| T-09-03 | DoS | re-prompt loop non-termination or suite hang | medium | mitigate | `for attempt in 1 2` visible bound — exhaustion returns 1 through the same cancel chain Esc uses; harness stub replaces the binary's `done_file` spin-wait | closed |
| T-09-04 | Tampering | free-text menu answer → `target_bytes` → filename/argv | medium | mitigate | `parse_target_size` reused verbatim; only integer bytes and the canonical `numfmt --to=si` token propagate (decimal since `4d422ffe`); planner refusals terminal per D-01 | closed |
| T-09-05 | DoS | unstubbed/mis-stubbed `omarchy-menu-input` → silent hang or false green | medium | mitigate | stub shipped in the same commit; `menu-input:` logged before the knob decision; unset knob exits 1 as the Esc/tripwire state | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

**Closure evidence (L1):** T-09-01 — `bin/omarchy-transcode` sentinel branch format-gated on `mp4` (WR-01 fix `79928688`); forged-gif e2e pin green; sentinel-leak sweep proves no `Custom`/`target:` on any `ffmpeg`/`out=` line. T-09-02 — unwrap at `main()` menu gate with `^[0-9]+$` guard; verifier 10/10 must-haves. T-09-03 — `prompt_target_size` `for attempt in 1 2` bound; stub pins empty-submit vs Esc three-state behavior. T-09-04 — interactive run ≡ `--target` argv byte-identical (normalized-passdir `cmp` pin). T-09-05 — `omarchy-menu-input` stub shipped in `1fd54ced`; 93/93 e2e green.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-09-01 | T-09-01 | Sentinel label spoofable only by a forged menu response, not user-reachable input — the format gate reduces it to defense-in-depth | plan + review (WR-01) | 2026-09-18 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-18 | 5 | 5 | 0 | Devin (gsd-secure-phase, L1 — ASVS 1 short-circuit: register authored at plan time, threats_open 0) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-18
