# Stack Research

**Domain:** CLI media transcoding — quality tiers and output-size estimation for `bin/omarchy-transcode` (bash + ffmpeg + ImageMagick)
**Researched:** 2026-09-15
**Confidence:** HIGH for CRF tier values, fps-as-gif-lever, and ffprobe-based estimation approach; MEDIUM for the bitrate midpoint table (CRF output bitrate legitimately varies ±2x with content — that's inherent to CRF, not a research gap)

## Recommended Stack

### Core Technologies — no new dependencies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| ffmpeg + libx264 | system (Arch `extra/ffmpeg`, unpinned) | mp4 encode at 720p/1080p | Already the tool; CRF mode is the right quality-tier primitive because bitrate floats to hold perceptual quality constant across content types |
| ffmpeg + libx265 | same package | mp4 encode at 2160p | Same; kept resolution-gated (4k only) to preserve current codec-selection behavior |
| ffprobe | same package | Duration probe for size estimation | The designed primitive for this: instant container parse, no decode. Nothing cheaper exists without decoding the stream |
| ImageMagick (`magick`) | system | Picture transcode | Unchanged — pictures get no quality step (TRANSC-06) |
| `numfmt --to=iec` (coreutils) | system | Humanize estimated + actual byte counts | Exact bytes→human for `stat -c %s` output; repo precedent `du -h` works too but numfmt is cleaner for computed estimates |
| awk | system | Float math for duration×bitrate | bash can't do floats; awk is already the repo's float-math convention (see `omarchy-hyprland-monitor-scaling`, `omarchy-network-speedtest`) |

## Quality Tiers — concrete numbers

### x264 (720p, 1080p — `-preset fast` stays fixed)

| Tier | CRF | Size vs medium | Why this value |
|------|-----|----------------|----------------|
| high | **18** | ~1.8× | Canonical "visually lossless" point on the 0–51 scale; real headroom above the default |
| medium | **23** | 1× | LOCKED — must reproduce current `-crf 23` exactly (TRANSC-02). Also the encoder's own default |
| low | **28** | ~0.45× | Floor of the sane delivery range (18–28); beyond ~30 artifacts dominate even at share quality |

### x265 (2160p only — `-preset slow` stays fixed)

| Tier | CRF | Size vs medium | Why this value |
|------|-----|----------------|----------------|
| high | **20** | ~1.6× | Very high quality; x265 CRF 20 ≈ x264 CRF ~15 perceptually |
| medium | **24** | 1× | LOCKED — reproduces current `-crf 24`. Already quality-biased (≈x264 CRF 19) |
| low | **28** | ~0.5× | x265's own default; ≈x264 CRF 23 perceptually — "still fine" floor for sharing |

**Why the scales differ:** x265 CRF ≈ x264 CRF + 5 for rough perceptual parity (x265 default 28 ≈ x264 default 23). Never copy a CRF number across codecs. **Why ±5–6 steps:** each +6 CRF ≈ halves bitrate for x264 (~5.3 for x265) — so the tiers above produce a meaningful ~2× spread each direction instead of indistinguishable rows. **Why presets stay fixed:** `-preset` trades encode time for size efficiency at a given CRF — it doesn't define "quality" the way users mean it, and varying it per tier muddies the "medium = today's flags" invariant. If `high=18` makes files feel too large, the cheaper alternative is `high=20` (~1.4×).

## Size Estimation

**Primitive:** `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -- "$input"` — one call, ~ms, no decode. Guard `[[ $dur =~ ^[0-9.]+$ ]]`; some containers report `N/A` — fall back to `-select_streams v:0 -show_entries stream=duration` or just omit the subtext. No better cheap estimator exists; anything content-aware requires decoding.

**Formula:** `est_MB = dur_s × (video_kbps + 192) / 8192` via awk. **Include the 192k AAC audio** (24 KB/s ≈ 1.4 MB/min) — at low/720p it's ~25% of the output; skipping it makes low-tier estimates visibly optimistic.

**Video bitrate midpoints (typical mixed content; real output varies ±2x — camera/action higher, screen capture/talking-head lower):**

| Resolution | Codec / CRF tiers | high | medium | low |
|------------|-------------------|------|--------|-----|
| 720p | x264 18/23/28 | 2.5 Mbps | 1.5 Mbps | 0.7 Mbps |
| 1080p | x264 18/23/28 | 5.5 Mbps | 3.0 Mbps | 1.4 Mbps |
| 2160p | x265 20/24/28 | 16 Mbps | 9 Mbps | 4.5 Mbps |

Grounding: 1080p x264 CRF 23 lands ~1–4 Mbps across content (≈2.6 Mbps on high-complexity Blender footage; ~0.8 Mbps on simple content); the table takes midpoints and scales ~∝ pixels across resolutions and ~∝2^((23−CRF)/6) across tiers. Display with a `~` prefix and 1–2 sig figs ("~45 MB") so it reads as an estimate — TRANSC-03 says estimates must be clearly approximate. Actual size post-encode: `stat -c %s "$output" | numfmt --to=iec`.

## GIF Tiers

**fps is the right "quality" lever** (TRANSC-01 already decides this): it's the only knob that is both near-linear in output size AND reads to users as quality (smoothness). Recommended: **high = 15 fps, medium = 10 fps (locked, current), low = 5 fps** → ~1.5× / 1× / ~0.5× size. (8 fps is the gentler low if 5 feels too choppy.)

Secondary levers — deliberately untouched: `palettegen=max_colors=N` (256 default; 128 saves ~10–20%, bands on gradients) and `paletteuse=dither=` (sierra2_4a default; `bayer:bayer_scale`/`none` shrink but look worse). Optional pairing: `max_colors=128` on the low tier only. Don't vary lanczos or add a second palette pass.

**GIF estimates: omit them.** GIF size is content-dominated to the point a table is misleading — 10 s of flat desktop capture ≈ 1–3 MB, the same 10 s of noisy camera video at 1080p10 ≈ 20–60 MB (a 20–30× spread vs mp4's ~2×). TRANSC-03 scopes subtext estimates to mp4 anyway. If estimates are ever wanted, scale a coarse per-resolution baseline linearly by fps/10: 720p ≈ 0.4 MB/s, 1080p ≈ 0.9 MB/s, 2160p ≈ 2.5 MB/s — labeled "varies widely".

## Installation

```bash
# Nothing to install. ffmpeg/ffprobe, imagemagick, coreutils (numfmt),
# and gawk are all present in the Omarchy default package set.
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Fixed duration×bitrate table | Scale estimate by source bitrate from `ffprobe format=bit_rate` | If real-world testing shows the flat table consistently wrong for the fork owner's actual files. The ratio varies too much with source codec (already-efficient sources re-encode *up* at CRF 18) to be reliably better — keep it simple first |
| ffprobe duration | mediainfo | Never here — extra dependency for identical data |
| awk float math | `bc` | awk wins: already the repo's float convention, one fewer tool to spawn |
| CRF tiers | `-b:v` bitrate tiers | CRF holds *quality* constant; a fixed-bitrate tier would punish complex content and waste bits on simple content — wrong semantics for a quality picker |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Two-pass encoding (`-pass 1/-pass 2`) | Meaningless under CRF — pass 1 exists to calibrate a *bitrate* target; CRF deliberately lets bitrate float. Would double encode time for zero benefit | Single-pass CRF (current). Only relevant for a future `--target-size` mode: compute `b:v = (target_bits − 192k×dur) / dur`, run two passes with `-an`+null-muxer pass 1, optionally `-maxrate`/`-bufsize` caps — ~2× encode time, keep as documented future work |
| `-b:v`/`-maxrate` caps on CRF | Turns quality mode into bitrate mode and reintroduces the "complex content starves" problem CRF solves | Plain `-crf` |
| Per-tier `-preset` changes | Changes encode time and size-efficiency, not user-visible "quality"; blurs the medium-is-current-flags contract | Keep `fast` (x264) / `slow` (x265) fixed |
| Picture quality menu step | TRANSC-06: jpg/png flow unchanged, no third prompt | If a CLI-only jpg quality arg lands later: `-quality` 92 / 85 (current) / 75. Do NOT map it onto png — IM's png `-quality` is a zlib-level×10+filter composite; the existing `-define` flags are already correct |
| Decoding/sampling the input to estimate | Frames-accurate estimates need a real decode — absurd cost for a menu subtext | ffprobe duration + table |

## Stack Patterns by Variant

**If the quality row needs an estimate subtext (mp4):** pass options as `high\t~120 MB` style `label<TAB>subtext` — `omarchy-menu-select` renders subtext under the label, but returns `"label<TAB>subtext"`, so the caller must strip it: `quality="${selection%%$'\t'*}"`.

**If `medium` should be the Enter-default (TRANSC-05):** `omarchy-menu-select` builds its payload via perl `JSON::PP` — add an optional `defaultIndex` integer; `Menu.qml` `openDmenu()` hardcodes `selectedIndex = 0` (shell/plugins/menu/Menu.qml:874) — clamp `payload.defaultIndex` to `[0, options.length-1]` there. All other callers default to 0 unchanged.

**If ffprobe returns empty/`N/A` duration:** build quality rows without subtext — a row with no third field is legal, and a missing estimate beats a wrong one.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `omarchy-transcode` | system ffmpeg | `ffmpeg` isn't listed directly in `install/omarchy-base.packages` — it arrives transitively (e.g. `ffmpegthumbnailer`, `qt6-multimedia-ffmpeg`). Status quo already relies on it; this change adds no new requirement, but don't add `omarchy-cmd-present` guards — ffmpeg is a de-facto runtime invariant here |
| ffprobe | ffmpeg | Same package, always co-installed |
| `numfmt`, `stat` | coreutils | Always present on Arch |
| CRF flag syntax | all libx264/libx265 builds | `-crf` is stable across every relevant ffmpeg version; no version guard needed |

## Sources

- ffmpeg-micro.com CRF guide — x264 sane range 18–28, ±6 ≈ half/double, x265 default 28 ≈ x264 23; per-codec landmark CRFs (HIGH confidence, consistent with ffmpeg wiki conventions)
- video.stackexchange #16664 + Doom9 x265↔x264 CRF mapping — "scales do not correspond; x265 CRF 28 ≈ x264 CRF 23" (HIGH confidence consensus)
- Gough's Tech Zone x264/x265 CRF curves — measured ~6.05 (x264) / ~5.34 (x265) CRF steps per 2× bitrate (MEDIUM-HIGH, empirical on film content)
- vibbit.ai / browsercut.com compression guides — real-world CRF 23 file-size ranges, content-variance magnitude (MEDIUM)
- Repo: `bin/omarchy-transcode` (current flags), `bin/omarchy-menu-select` (subtext/return contract), `shell/plugins/menu/Menu.qml:861-881` (`openDmenu` payload handling, `selectedIndex` init)

---
*Stack research for: omarchy-transcode quality tiers + size estimation*
*Researched: 2026-09-15*
