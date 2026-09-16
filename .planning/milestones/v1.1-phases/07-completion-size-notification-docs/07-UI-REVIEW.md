---
phase: 07-completion-size-notification-docs
reviewed: 2026-09-16
scope: notification-body text change only (no QML/frontend files touched)
score: n/a — single-surface change verified via running-UI UAT
status: reviewed
---

# Phase 7 — UI Review

## Scope

The phase's only user-visible change is the transcode done-notification body:
`Saved and copied to clipboard (N MB).` (video + picture arms) plus the `<1 MB` floor for sub-MiB outputs. No QML, no menu rows, no layout — the 6-pillar visual audit has no surface to score here; this record documents the single-surface check instead.

## Verified

| Check | Result | Evidence |
|-------|--------|----------|
| Toast renders the size legibly in the running UI | ✓ | UAT test 1 — user confirmed a real transcode's done toast showed `121 MB` |
| PUA glyphs intact (U+F03D video / U+F03E picture) | ✓ | Byte-verified in review (`EF 80 BD` ×2, `EF 80 BE` ×1); UAT test 1 showed the glyph rendered |
| Honest degradation | ✓ | stat failure → plain `Saved and copied to clipboard.` (harness row); sub-1 MiB → `(<1 MB)`, never `(0 MB)` (`972a1bba`) |
| Manual prose consistent with UI | ✓ | UAT test 3 — `manual/12` names the quality step, the estimate, and the actual-size notification in end-user language |

## Advisory (non-blocking)

- `manual/12:72`'s "check it against the estimate" applies to videos only — pictures get an actual size but never saw an estimate. Accepted as written in UAT test 3; tighten in a future docs pass if it reads oddly.

## Result

Clear — single-surface change verified end-to-end in the running UI.
