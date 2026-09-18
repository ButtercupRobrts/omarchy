# Phase 9 — Deferred Items

Informational findings from `09-REVIEW.md` (code review, 2026-09-17) and the senior audit (2026-09-18). None block completion; each is recorded for future passes.

## Items

- **IN-02** — Mint-guard `return 1` (main unwrap) vs `--target`'s `return 2` for the same `Invalid target size` class — unreachable by construction (the mint only produces `^[0-9]+$`), consistency note only. Cosmetic; align if the block is touched again.
  status: acknowledged
- **IN-04** — `192k` audio bitrate is a magic constant in 4 sites (`-b:a 192k` in `transcode_video` ×2 and `transcode_video_target` ×2) plus `video_audio_kbps`'s probe return — a future audio-bitrate change must move all five together. Not extracted now: doing so would touch v1.1 lines inside the PR #12135 review window. Extract to a shared constant after upstream merge.
  status: acknowledged
- **IN-05** — `estimate_label` and `plan_target`'s refusal `min_label` each encode the `(rate_kbps) * duration * 125` bytes formula independently — same PR-window constraint as IN-04. Dedupe alongside IN-04 post-merge.
  status: acknowledged
