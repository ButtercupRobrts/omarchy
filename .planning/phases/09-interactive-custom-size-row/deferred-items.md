# Phase 9 — Deferred Items

Informational findings from `09-REVIEW.md` (code review, 2026-09-17). None block completion.

| Ref | Item | Disposition |
|-----|------|-------------|
| IN-02 | Mint-guard `return 1` (main unwrap :640-641) vs `--target`'s `return 2` for the same `Invalid target size` class — unreachable by construction (the mint only produces `^[0-9]+$`), consistency note only | cosmetic; align if the block is touched again |
| IN-04 | `192k` audio bitrate is a magic constant in 4 sites (`-b:a 192k` in `transcode_video` ×2 and `transcode_video_target` ×2) plus `video_audio_kbps`'s probe return — a future audio-bitrate change must move all five together. Not extracted now: doing so would touch v1.1 lines inside the PR #12135 review window | extract to a shared constant after upstream merge |
| IN-05 | `estimate_label` and `plan_target`'s refusal `min_label` each encode the `(rate_kbps) * duration * 125` bytes formula independently — same PR-window constraint as IN-04 | dedupe alongside IN-04 post-merge |
