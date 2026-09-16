# Requirements: Omarchy Fork — Transcode Quality & Size Feedback

**Defined:** 2026-09-15
**Core Value:** A transcode invoked for sharing should let the user trade quality for size knowingly — pick a quality tier, see roughly how big the result will be, and get the actual size when it finishes — without slowing down the default path.

## v1.1 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Quality Selection

- [x] **QUAL-01**: The video transcode flow offers a quality step (high/medium/low) after format and resolution; mp4 maps to CRF tiers (x264 18/23/28, x265 20/24/28), gif maps to fps tiers (15/10/5)
- [x] **QUAL-02**: Quality is an optional 4th positional arg (`omarchy transcode in.mov mp4 1080p medium`); `medium` or omitted reproduces current encoder flags exactly — backward compatible for the Nautilus extension and scripts
- [x] **QUAL-03**: Pictures never see the quality step; the 4th positional arg is rejected for image inputs (`high/medium/low` in slot 3 remains picture resolution)

### Size Feedback

- [x] **SIZE-01**: mp4 quality menu rows show a `~N MB` estimate as subtext (ffprobe duration × per-resolution/tier bitrate table + fixed 192k audio); gif rows show fps instead of a size estimate
- [x] **SIZE-02**: The completion notification reports the actual output file size

### Menu Infrastructure

- [x] **MENU-01**: `omarchy-menu-select` supports a pre-highlighted default row (`--default-index N` passed after `--`, carried through the JSON payload to `Menu.qml` `openDmenu`); all existing callers behave unchanged

### Output Safety

- [x] **SAFE-01**: Output filename gains a quality suffix only for non-default quality (`stem-1080p-low.mp4`, `stem-1080p.mp4` stays for medium); overwrite behavior is deliberate and safe on non-interactive launch paths (no ffmpeg stdin-prompt hangs or silent aborts)

## v2 Requirements

Deferred to a future milestone. Tracked but not in the current roadmap.

### Sizing & Intent

- **SIZE-10**: `--target 25M` two-pass encode mode — computes `-b:v` from duration and runs `-pass 1/2` to hit a byte budget (the honest way to promise "fits Discord")
- **SIZE-11**: Intent presets (e.g. "for chat", "for archive") — conflicts with the CRF tier model; only viable on top of SIZE-10
- **SIZE-12**: gif size estimates — 20–30× content spread makes a table misleading; needs a sample-encode estimator if ever done
- **QUAL-10**: Picture quality CLI arg (jpg `-quality` 92/85/75); png stays untiered — its `-quality` is a zlib composite, not perceptual quality
- **QUAL-11**: Nautilus multi-select batch remembers the quality/format answers instead of re-prompting per file (aligns with open upstream PR #6698's direction)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Codec or bitrate controls (sliders, raw CRF input, `-b:v`/`-maxrate`) | Violates the named-tier UX; CRF is logarithmic and meaningless to expose |
| Sample-encode preview estimates | Adds seconds of latency before a menu meant to feel instant; `~` table is the honest tradeoff |
| Progress indication during encode | Notification already brackets the operation; ffmpeg progress UX is a different feature |
| Quality prompt for pictures | Resolution is already the size knob; jpg quality delta is marginal for sharing |
| Per-tier `-preset` changes | Preset is a speed knob, not a quality knob; keep `fast`/`slow` as-is |
| Building on open PR #6698's branch | Same-script conflicts noted; independent change stays reviewable — plan for rebase, not dependency |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| MENU-01 | Phase 4 | Complete |
| QUAL-02 | Phase 5 | Complete |
| QUAL-03 | Phase 5 | Complete |
| SAFE-01 | Phase 5 | Complete |
| QUAL-01 | Phase 6 | Complete |
| SIZE-01 | Phase 6 | Complete |
| SIZE-02 | Phase 7 | Complete |

**Coverage:**

- v1.1 requirements: 7 total
- Mapped to phases: 7
- Unmapped: 0 ✓

### Previous Milestones

v1.0 "Per-Monitor Display Scaling" — SCALE-01..10 all Complete (phases 1–3). See `.planning/milestones/archived-20260914-phases/` for phase artifacts.

---
*Requirements defined: 2026-09-15*
*Last updated: 2026-09-15 after milestone v1.1 definition*
