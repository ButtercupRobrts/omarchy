# Feature Research

**Domain:** Quality-vs-size tradeoff UX in media transcode/compress-for-sharing tools
**Researched:** 2026-09-15
**Confidence:** HIGH on how comparators behave (well-documented); MEDIUM on transferability to a keyboard-first shell menu

## Feature Landscape

Two dominant mental models exist in this space, and the choice between them drives everything else:

- **Constant-quality (CRF) model** — HandBrake, most ffmpeg wrappers: the user picks a quality level; output size is a variable consequence. Size feedback is necessarily approximate (±20–30%, content-dependent).
- **Target-size model** — 8mb.video, discord-encode, deepshrink: the user picks an outcome ("fit under N MB"); the tool does bitrate math and a two-pass encode to *guarantee* the size. Quality is the derived variable.

This milestone is locked on the CRF model (medium = today's exact flags, table-based estimates). The research below validates that choice for a "quick share" flow and maps what users expect within it.

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Named quality tiers (high/medium/low) | Every consumer flow uses plain language; raw CRF numbers appear only in power-user tools (ShareX form fields, HandBrake advanced) | LOW | Map tiers to CRF/fps internally; never surface the number |
| A pre-selected sane default | HandBrake presets ship tuned defaults; 8mb.video defaults to 8MB. The "just hit Enter" path must exist | LOW | `medium` pre-highlighted via new `defaultIndex` in `omarchy-menu-select` (TRANSC-05) |
| Some size signal before committing | Mobile compressors show live estimated size; HandBrake's preset tables give qualitative Small/Average/Large. Users consistently ask "how big will it be?" | MEDIUM | `ffprobe` duration × per-tier bitrate table → "~N MB" subtext (TRANSC-03) |
| Actual output size at completion | Universal in compressor tools (before/after stats, "post-mortem reports"); closes the estimate→reality loop | LOW | `stat` the output in the completion notification (TRANSC-04) |
| Non-interactive parity | Every CLI comparator (`discord-encode -size`, `deepshrink --target`, ShareX actions) accepts args; a menu-only feature breaks scripting | LOW | 4th positional arg; omitted/`medium` reproduces current flags byte-for-byte (TRANSC-02) |
| Honest approximation labeling | CRF output is content-adaptive; estimators universally caveat ±20–30%. "~" prefix is the honest signal | LOW | "~14 MB", never "14.2 MB" |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Per-option size estimate as subtext on quality rows | Mobile apps (Video Compressor HD, video_compress_kit) offer a live estimate; almost no keyboard/menu tool does. Turns an abstract tier into a concrete decision | MEDIUM | Estimate = duration × tier bitrate; feasible only because resolution is already chosen — see dependency notes |
| Estimate→actual feedback loop in notification | No comparator shows both "we guessed ~X" up front and "it landed at Y" on completion. Calibrates user trust in the table over time | LOW | Falls out of TRANSC-03 + TRANSC-04 together |
| Intent-based presets ("discord" → fits 10MB) | 8mb.video's whole success is naming the outcome, not the setting. One-word answer to "will this upload?" | HIGH | Requires either verified bitrate ceilings per tier or target-size mode; real intent presets need guarantees a CRF table can't give — candidate for v2 |
| Target-size two-pass mode | discord-encode/deepshrink guarantee ≤ N MB via bitrate math + two passes. The only way to make "fits X" a promise instead of a guess | HIGH | ~2× encode time; contradicts "fast default path" if it ever becomes default. Keep as opt-in mode if added at all |
| Same quality vocabulary for gif | gif quality expressed as fps tiers under the same high/medium/low names — coherent UX across formats | LOW | Already planned (TRANSC-01); gif estimates are a stretch (palette encoding doesn't follow bitrate tables cleanly) |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Bitrate slider / raw CRF entry | "Give me control" — ShareX exposes CRF number boxes | Demands codec literacy; x264 CRF is logarithmic (~12.8% size change per point, ±6 ≈ half/double) — meaningless to most users; breaks keyboard-minimal menu | Named tiers over tuned internal values |
| Codec sprawl (x264/x265/VP9/AV1 per encode) | "Why not AV1?" | Decision paralysis in a "quick share" flow; each codec needs its own estimate table and compatibility story. Omarchy's contract is opinionated defaults | Keep the existing implicit choice (x265 only at 4k); revisit only if compatibility complaints appear |
| Fake precision estimates ("14.2 MB") | Looks more rigorous | CRF is content-adaptive: same settings yield wildly different sizes on grainy vs. flat content. False precision erodes trust when reality diverges | "~14 MB" rounded to 2 sig figs + actual size at completion |
| Sample-encode preview for accurate size | HandBrake docs push "encode a few chapters to check" | Costs real encode time inside a flow whose whole point is speed; locked decision already rules this out | Table-based "~" estimates |
| Estimates on BOTH resolution and quality steps | "More information is better" | Resolution-step estimate must assume a quality → either a lie or a "~20–90 MB" range too wide to act on. Pure noise | Estimate once, on the final decision (quality), where all inputs are known |
| Guaranteed size claims without two-pass | Users want "under 10MB" assurance | CRF cannot promise a ceiling; claiming one is dishonest and will be wrong on complex sources | If guarantees are needed, that's target-size mode (v2) — never imply one from a CRF estimate |
| Remember-last-quality / per-format sticky defaults | "Save me the prompt" | Silent behavioral drift between runs; the medium default exists precisely to be predictable | Keep stateless; positional arg covers repeat non-interactive use |

## Feature Dependencies

```
[Quality menu step]
    └──requires──> [ffprobe duration probe + bitrate table]
    └──requires──> [resolution already chosen]  (sequential flow guarantees this)
    └──requires──> [defaultIndex in omarchy-menu-select]  (medium pre-highlight)

[Per-row size estimates]
    └──requires──> [ffprobe duration probe + bitrate table]
    └──enhanced-by─> [actual size in completion notification]  (calibration loop)

[Intent presets ("discord")]
    └──requires──> [target-size two-pass mode]  ──conflicts──> [fast single-pass default path]
```

### Dependency Notes

- **Quality step requires the resolution step first:** the estimate needs resolution to pick a bitrate-table row. The existing file → format → resolution order already guarantees this; quality slots in last.
- **Per-row estimates require ffprobe + a table:** one `ffprobe` call for duration (~ms), multiplied by per-(format, resolution, quality) bitrate entries. No encode needed.
- **defaultIndex requires a `omarchy-menu-select`/`Menu.qml` change (TRANSC-05):** the "Enter = medium" contract depends on plumbing a default row index through the select payload.
- **Intent presets conflict with the CRF tier model:** "fits Discord free tier" is a promise about bytes; CRF makes promises about quality. Delivering it honestly requires two-pass target-size encoding — a different mode, not a fifth tier.

## MVP Definition

### Launch With (v1.1)

Minimum viable product — what's needed to validate the concept.

- [ ] Quality step for video only (mp4 CRF tiers, gif fps tiers) — the core interaction being validated (TRANSC-01)
- [ ] `medium` pre-highlighted; omitted/`medium` reproduces today's flags exactly — zero-friction default path and non-interactive safety (TRANSC-02, TRANSC-05)
- [ ] "~N MB" estimate subtext on mp4 quality rows — the differentiating feedback, at the step where all inputs are known (TRANSC-03)
- [ ] Actual size in completion notification — closes the loop (TRANSC-04)
- [ ] Pictures skip the step entirely; quality suffix only when non-default — protects the unchanged picture flow (TRANSC-06)

### Add After Validation (v1.x)

Features to add once core is working.

- [ ] gif estimate subtext — if mp4 estimates prove useful; needs its own table since palette-gif size tracks fps/area, not bitrate
- [ ] Range estimates on resolution rows — only if users report picking resolution blind; format "~a–b MB" honestly

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] Target-size two-pass mode (`--target 8MB` / "discord" intent preset) — high value for the Discord use case but 2× encode cost and a parallel code path; validate demand first
- [ ] Audio-quality tier or mute option — second-most-common knob after video quality, but adds a dimension the three-tier model doesn't cleanly hold

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Named quality tiers for video | HIGH | LOW | P1 |
| Pre-highlighted medium default | HIGH | LOW-MEDIUM | P1 |
| Per-row "~" size estimates (mp4) | HIGH | MEDIUM | P1 |
| Actual size in notification | MEDIUM | LOW | P1 |
| Pictures skip step / conditional suffix | HIGH | LOW | P1 |
| gif size estimates | LOW | MEDIUM | P2 |
| Intent presets / target-size mode | MEDIUM | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | HandBrake | 8mb.video / CLI compressors | ShareX | Our Approach |
|---------|-----------|------------------------------|--------|--------------|
| Quality model | CRF slider (0–51, logarithmic) + presets bundling speed/res/quality | None — quality is derived from a size target | Raw CRF number box + preset dropdown | Three named tiers mapped to CRF (mp4) / fps (gif); medium = current flags |
| Pre-encode size info | None numeric; preset tables say "Small/Average/Large"; docs recommend test-encoding chapters | The chosen target IS the size — guaranteed by two-pass | None | "~N MB" per-row estimate via duration × bitrate table |
| Post-encode size info | Output file on disk | Before/after stats common ("post-mortem reports") | Output file on disk | Actual size in completion notification |
| Default path friction | Pick preset, hit start | Pick size, upload | Configure once in settings | file → format → resolution → Enter on medium; 4th positional arg skips all prompts |
| Where the estimate lives | N/A (refuses to estimate) | N/A (guarantees instead) | N/A | Final decision step (quality), where resolution+format are already known |

**On estimate placement:** Mobile compressors show one live estimate that updates as any parameter changes — the functional equivalent of "estimate shown when all inputs are set." In a sequential menu, that means the last step. An estimate on the resolution step would need either an assumed quality (dishonest) or a range wide enough to be useless ("~20–90 MB"). HandBrake sidesteps this by bundling everything into one preset row; we approximate the same single-decision-with-size-info by putting the estimate on the final step.

## Sources

- HandBrake docs: Adjusting Quality (recommended RF ranges), Constant Quality vs ABR ("output size is unpredictable"), Official Presets + Performance tables (qualitative Small/Average/Large sizes)
- 8mb.video and ecosystem coverage (VideoProc, HitPaw, Wondershare writeups): target-size UX — pick 8/25/50/100MB, tool handles the rest
- GitHub CLI wrappers: aWZHY0yQH81uOYvH/discord-encode (two-pass ABR, `-size` flag), deeplabua/deepshrink (`--target 8MB`, `--for discord`, `--dry-run`), nunogomes255/ffmpeg-shrinkwrap (bitrate math + rescue-mode fallback chain), crusader290/8mb-Video-Compressor (adaptive downscale when bitrate floor hit)
- ShareX source: FFmpegOptions.cs / FFmpegOptionsForm.cs — codec/preset/CRF/bitrate exposed as raw form fields
- Mobile/SDK: MWM Video Compressor HD (real-time size estimation), video_compress_kit (`estimateFileSize` API)
- Estimators: ffmpeg-cookbook filesize estimator (±30% caveat), favtoo video size estimator (empirical bits-per-pixel, ±20%), Stack Overflow #73673626 (~12.85% size change per CRF point)
- ffmpeg-cookbook two-pass encoding article: `total_bitrate = (target_MB × 8192) / duration_s` formula, CRF vs two-pass decision table

---
*Feature research for: omarchy-transcode quality selection & size estimation*
*Researched: 2026-09-15*
