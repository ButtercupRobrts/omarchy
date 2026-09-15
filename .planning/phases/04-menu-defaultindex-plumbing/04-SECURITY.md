---
phase: "04"
slug: "menu-defaultindex-plumbing"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-15"
---

# Phase 04 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| CLI → shell summon | `--default-index` is caller-controlled input crossing argv → JSON payload (`omarchy-shell shell summon`) → QML `selectedIndex` | Caller-supplied integer; low sensitivity — worst case is highlight position |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-04-01 | Tampering | `defaultIndex` payload → QML cursor state | medium | mitigate | `MenuModel.dmenuDefaultIndex` floor/NaN/negative/clamp coercion + existing `rebuildDmenuDisplay` bounds; regex-gated `int()` emission coerces non-finite values to 0 (WR-01 fix, `634aea54`) | closed |
| T-04-02 | Confusion | `--default-index` token reaching the pre-`--` option stream | medium | mitigate | Flag parses only inside the post-`--` case loop — can never enter the option stream or the `mapfile` stdin fallback; value-required guard exits 1 before any payload is built | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

**Closure evidence (L1):** T-04-01 — 11 node cases + e2e green: `99`→last row, `-3`/`abc`/`1e1000`→`0`; worst outcome is a moved highlight (rows render `Text.PlainText` — no markup injection). T-04-02 — e2e "keeps the stdin option stream intact" + "rejects --default-index without a value" green; caller sweep shows no pre-`--` usage.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-04-01 | T-04-01 | Out-of-range index silently clamps to the last row rather than erroring — specified behavior per D-04 | plan (CONTEXT.md D-04) | 2026-09-15 |
| R-04-02 | T-04-02 | A `--default-index`-shaped token placed *before* `--` still becomes a menu row by design — the contract places the flag after `--` and docs/menu.md says so | plan (CONTEXT.md D-01) | 2026-09-15 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-15 | 2 | 2 | 0 | Devin (gsd-secure-phase, L1 — ASVS 1 short-circuit: register authored at plan time, threats_open 0) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-15
