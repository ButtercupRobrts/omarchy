---
phase: "05"
slug: "non-interactive-quality-in-omarchy-transcode"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-15"
---

# Phase 05 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| caller argv → `main()` | positional quality value, input path, format, and resolution are caller-controlled; the `file` MIME verdict on the input is attacker-craftable | Caller-supplied strings; quality is the new surface |
| `main()` → `ffmpeg`/`magick` argv | validated values cross into encoder command lines | Quality becomes CRF/fps digits only after whitelist |
| `output_path()` → filesystem | the computed output name becomes a real file written next to the input | Suffix + dedupe counter; only `high`/`low` literals can reach the name |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-05-01 | Tampering | `output_path()` dedupe loop | high | mitigate | `while [[ -e $candidate \|\| -L $candidate ]]` — the `-L` covers dangling symlinks that `-e` misses; without it ffmpeg would write through the link to an unrelated target | closed |
| T-05-02 | Tampering | quality arg → filename/argv | medium | mitigate | `high\|medium\|low` whitelist enforced in `main()` before `output_path` sees the value; whitespace-padded and `*`-shaped values rejected; no traversal or flag injection | closed |
| T-05-03 | DoS | ffmpeg stdin overwrite prompt on detached/keybind launch | high | mitigate | dedupe removes the only interactive surface — ffmpeg never sees an existing target, so no `[y/N]` read can hang a tty-less launch; no overwrite-forcing flag added (D-01) | closed |
| T-05-04 | Tampering | TOCTOU between dedupe check and ffmpeg open | low | accept | a file materializing in the gap degrades to today's prompt/refuse behavior — never a silent clobber; the window is inherent to any check-then-write | closed |
| T-05-05 | Info/Tampering | `file` MIME output → `media_type` glob | low | accept | attacker-controlled MIME strings only feed `image/*`/`video/*` glob matching and an error echo — no eval, no arithmetic | closed |
| T-05-06 | Tampering | `format` value → filename extension | low | accept | a `--`-passthrough like `a/b` yields `stem-1080p.a/b`, `-e` is false, ffmpeg fails on open — pre-existing, quoted, no worse than today | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

**Closure evidence (L1):** T-05-01 — `[[ -e || -L ]]` loop at `bin/omarchy-transcode:65-70`; dangling-symlink fixture row green in `transcode-quality-test.sh` (29/29). T-05-02 — validation block at `bin/omarchy-transcode:205-218` runs before `output_path`/notification; `bogus`, `" high"`, `"high "` rejected in tests; picture inputs reject any non-empty quality. T-05-03 — no `-y`/`-n`/`-nostdin` on any ffmpeg line (grep-verified); UAT 1/3 confirmed a second detached-path run produced `-2` with no prompt or hang.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-05-01 | T-05-04 | Dedupe-then-write race can at worst fall back to ffmpeg's existing interactive prompt — data loss impossible, UX degradation bounded to a rare manual-race | plan (threat register, T-05-04) | 2026-09-15 |
| R-05-02 | T-05-05 | `file` MIME verdict only selects between two fixed case patterns; no code path evaluates it | plan (threat register, T-05-05) | 2026-09-15 |
| R-05-03 | T-05-06 | Slash-bearing `format` via `--` passthrough produces a nonexistent-path encode failure, matching pre-existing behavior | plan (threat register, T-05-06) | 2026-09-15 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-15 | 6 | 6 | 0 | Devin (gsd-secure-phase, L1 — ASVS 1 short-circuit: register authored at plan time, threats_open 0) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-15
