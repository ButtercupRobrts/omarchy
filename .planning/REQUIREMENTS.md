# Requirements: Omarchy Fork — Target-Size Transcode

**Defined:** 2026-09-16
**Core Value:** A transcode invoked for sharing should let the user trade quality for size knowingly — v1.1 shipped the estimate→actual loop; v1.2 inverts it: name the size, get the best quality that fits.

## v1.2 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Size Targeting

- [x] **SIZE-10**: `omarchy transcode <video> [mp4] [res] --target 25M` parses free-text sizes (`25M`, `1.5G`, `500K`, `25MB`; bare number = MB) into integer bytes and two-pass encodes to hit the byte budget — video bitrate = `target×8 ÷ duration × ~0.98 reserve − 192k audio`; completion notification reports the actual size (existing SIZE-02 mechanism)
- [x] **SIZE-13**: Resolution auto-step-down — the planner picks the highest rung (4k → 1080p → 720p) whose video-bitrate floor fits the budget; the output filename and both notifications name the *actual* resolution used; when no rung fits, refuse with the achievable minimum size rather than produce a negative/zero bitrate
- [x] **SIZE-14**: Audio stays at fixed `-b:a 192k`; when the budget cannot fit 192k audio plus a viable video bitrate, refuse early — before menus/notifications — naming the minimum achievable target
- [x] **SIZE-15**: When a completed encode lands *over* the target, re-encode once with a tightened budget (scaled by the overshoot ratio); after one retry, report the actual size either way — never a silent loop

### Interactive

- [ ] **MENU-02**: The mp4 quality menu gains a `Custom size…` row → opens `omarchy-menu-input` for free-text entry → parsed by the same size parser → feeds the same target path; empty or unparseable input re-prompts once, then cancels cleanly (empty submit is exit-0-with-empty, not a cancel)

### Safety / Refusals

- [x] **SAFE-02**: `--target` is mutually exclusive with the positional quality arg (error naming both); refuses gif format (`-b:v` is verified meaningless for palette output) and picture inputs; fails fast before the start notification on missing value, unparseable size, or duration-probe failure

## v3 Requirements

Deferred to a future milestone. Tracked but not in the current roadmap.

- **SIZE-11**: Intent presets (e.g. "for chat") — viable on top of SIZE-10 once it ships
- **SIZE-12**: gif size estimates — needs a sample-encode estimator
- **QUAL-10**: Picture quality CLI arg (jpg `-quality` 92/85/75)
- **QUAL-11**: Nautilus multi-select batch remembers quality/format answers
- **SIZE-16**: Sub-720p resolution rungs (480p/360p) — only if dogfooding shows refusals at the 720p floor are common
- **SIZE-17**: Repeated overshoot correction loop — SIZE-15 caps at one retry; deeper convergence only if real misses appear

## Out of Scope

| Feature | Reason |
|---------|--------|
| `-fs` hard byte cap | Truncates mid-stream — a corrupt file that *meets* the target is worse than a few-% overshoot |
| Encode-until-converged loops | SIZE-15's single retry is the bound; convergence chasing doubles latency for diminishing returns |
| Upscaling to spend leftover budget | Target mode caps at `min(requested, source)` height; never upscale |
| Codec selection under `--target` | Resolution-keyed x264/x265 split stays — consistency over micro-optimization |
| Progress indication during encode | Two passes double encode time, but a progress UX is a separate feature; notification pair already brackets the operation |
| gif `--target` | Verified: palette encoder ignores `-b:v` entirely (byte-identical output at 100k vs 5000k) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SIZE-10 | 8 | Complete |
| SIZE-13 | 8 | Complete |
| SIZE-14 | 8 | Complete |
| SIZE-15 | 8 | Complete |
| MENU-02 | 9 | Pending |
| SAFE-02 | 8 | Complete |

**Coverage:**

- v1.2 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

### Previous Milestones

v1.0 "Per-Monitor Display Scaling" — phases 1–3, archived under `.planning/milestones/archived-20260914-phases/`.
v1.1 "Transcode Quality & Size Feedback" — phases 4–7, all requirements Complete. See `.planning/milestones/v1.1-REQUIREMENTS.md`.

---
*Requirements defined: 2026-09-16*
*Last updated: 2026-09-16 after milestone v1.2 roadmap*
