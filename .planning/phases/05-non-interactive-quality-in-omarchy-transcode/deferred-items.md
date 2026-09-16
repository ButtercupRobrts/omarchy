# Phase 5 — Deferred Items

Items surfaced during code review (05-REVIEW.md) that are out of scope for this phase.

## Warnings

- **WR-02 — Format/resolution validated after the start notification.** `omarchy transcode in.mov avi 1080p` sends "Transcoding video…" then fails `Invalid video format` inside `transcode_video`. Pre-existing asymmetry — the new quality check deliberately validates pre-notification, but format/resolution still validate at encode time. Fixing it means hoisting format/resolution validation into `main()` — a separate behavior change the plan explicitly forbade fixing silently. Candidate for a future phase if the orphaned-notification UX bothers anyone.
  status: acknowledged

## Info

- **`positional[5]`+ silently dropped** — pre-existing leniency, unchanged by this phase.
- **Unreachable defensive `*)` quality arm in `transcode_video`** — intentional (file idiom + sourced-function safety); keep.
- **Accepted TOCTOU (T-05-04)** — a file materializing between dedupe and ffmpeg's open degrades to today's prompt/refusal; never worse.
- **Unencoded `file://` URI spaces in `copy_to_clipboard`** — pre-existing; wl-copy/clipboard consumers tolerate it today.
- **Silent-exit grep extraction in test ordering assertion** — test-internal; `(( a < b ))` on empty vars would fail loudly anyway.
- **No-overwrite-flag pin is theoretically vacuous-passable** — acceptable; the dedupe assertions provide the real coverage.
- **Notifications omit the quality tier** — Phase 6/7 own notification content; the completion-size notification is SIZE-02.
  status: acknowledged
