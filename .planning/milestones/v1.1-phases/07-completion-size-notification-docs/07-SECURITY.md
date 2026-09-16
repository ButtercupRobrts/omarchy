---
phase: 07-completion-size-notification-docs
audited: 2026-09-16
asvs_level: 1
block_on: high
threats_total: 4
threats_open: 0
status: clear
---

# Phase 7 — Security Audit

ASVS Level 1 audit of the completion-notification size feature (`feat(07-01)` `22c28a7d`, `fix(07)` `8d52171b`, `fix(07)` `972a1bba`). Threat register carried from `07-01-PLAN.md` `<threat_model>` + research §Security Domain; each mitigation verified in source.

## Threat Register

| ID | Category | Threat | Severity | Disposition | Mitigation / Verification |
|----|----------|--------|----------|-------------|---------------------------|
| T-07-01 | Tampering | `stat` output → `awk -v` in `output_size_label` (awk `-v` interprets C escapes) | high | mitigate | `bytes=$(stat -c %s "$1" 2>/dev/null \|\| true)` then `[[ $bytes =~ ^[0-9]+$ ]] \|\| return 1` **before** `awk -v` — verified at `bin/omarchy-transcode:291-296`. Non-numeric output fails the helper; the caller degrades to the plain body. Same contract as the Phase-6 probes. Pinned by the T-07-degrade row. |
| T-07-02 | Integrity | Done notification claims a size for an output that doesn't exist | medium | mitigate | The done send sits after `transcode_*` under `set -e` — an encode failure aborts before it. Pinned by the `FAKE_ENCODE_RC=1` row (zero `Transcoded to` lines on failure) so a future reorder can't regress it. Verified: `test/shell.d/transcode-quality-test.sh` failure row green. |
| T-07-03 | Tampering (TOCTOU) | Output file swapped/deleted between encode and stat | low | accept | Benign — worst case reports the swapped file's size or degrades to the plain body; no write occurs and the path is one the script itself computed (`output_path` resolution). |
| T-07-04 | Injection | Size string → notification body → D-Bus | low | accept | Body is a typed `s` parameter in the busctl `susssasa{sv}i` call (`bin/omarchy-notification-send:184-199`); the label is digits + literal ` MB` (or `<1 MB`) by construction — nothing reaches a parser. |

## Concurrency note (flagged assumption, not a threat)

Two parallel transcodes sharing an output basename could each report the other's file at stat time — documented in `07-01-PLAN.md:388`, accepted (no locking, matches repo conventions; the report is informational).

## Result

- `threats_open: 0` — no high-severity threats unmitigated; the one `high` (T-07-01) is mitigated and test-pinned.
- Enforcement gate: **clear** (block_on: high).
