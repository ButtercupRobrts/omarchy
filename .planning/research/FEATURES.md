# Feature Research

**Domain:** Target-size ("fit under N MB") transcoding in consumer sharing tools — for `omarchy-transcode --target <size>` (SIZE-10) plus a "Custom size…" interactive row
**Researched:** 2026-09-16
**Confidence:** HIGH on comparator behavior and achievable accuracy (documented + empirically verified on the installed ffmpeg n9.0.1 in `research/STACK.md`); MEDIUM on which step-down floors feel right for our 3-rung ladder (comparator ladders are taller)

## Feature Landscape

This milestone switches the tool's mental model for one opt-in path. v1.1 shipped the **constant-quality model** (pick a CRF tier; size is an approximate consequence). `--target` adds the **target-size model** (pick an outcome; quality — and, under pressure, resolution — is the derived variable). The two models coexist cleanly because they answer different questions: "how good should it look?" vs "will it upload?".

How the comparators implement target-size, in ascending order of machinery:

| Tool | Budget model | Accuracy mechanism | Under-pressure behavior | UX surface |
|------|-------------|--------------------|-------------------------|------------|
| discord-encode | `total = size×8192/dur`, capped at 10 Mbps | Two-pass x264 ABR | None — just encodes at the derived rate | `-size <MB>` flag, default 10 |
| 8mb-Video-Compressor | ~90% video / 10% audio split | Two-pass VP9 + `-fs 8M` hard cap | Adaptive scale: ≥900k keep, 400–889k→480p, <400k→360p | Fixed 8 MB target |
| ffmpeg4discord | size/duration minus `-a 96k` audio | Two-pass **loop** — re-encodes until under target (`--approx` skips the loop) | `-r` explicit resolution only; no auto step-down | CLI flags + JSON config + web UI |
| ffmpeg-shrinkwrap | `TargetSizeMB` (default 9.8) − audio | Two-pass x265 + bitrate-convergence retries (max 3) | Waterfall: retry → 720p rescue at 500k floor → CRF 28 last resort → keyframe-aware split | PowerShell/Bash, tunable floors |
| deepshrink | `target×8×(1−0.02) − audio×dur`; audio snapped to a step ladder that leaves ≥60k video | Two-pass + **one** correction encode on overshoot | Resolution ladder (1080→144p, min-bitrate per rung); `Infeasible` (exit 4) below every floor | `--target`, `--reduce %`, `--for discord/email/…`, `--dry-run` |
| 8mb.video / 8mb.local | Same size/duration math | Two-pass; 8mb.local auto-retries when output >102% of target | 100 kbps minimum-bitrate error dialog ("Encode Anyway" override) | Web UI, preset buttons 8/25/50/100 + custom field |
| HandBrake | **Removed the feature** — see below | — | — | — |

The pattern that matters: every credible implementation converges on the same three moves — **subtract audio, reserve container overhead (~2%), two-pass** — and they differ only in how hard they chase the last few percent (retry loops) and how far down the resolution ladder they're willing to go (480p/360p/240p rungs we don't have).

## Table Stakes (users expect these)

| Feature | Why expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Bare-number input meaning MB | Every comparator accepts `-size 25` / `--target 8MB` / a plain number field; MB is the universal unit of the problem | LOW | Accept `25`, `25M`, `25MB`, `25m`, `1.5G`; `numfmt --from=iec` is stricter than free text deserves — regex-gate then normalize (STACK.md verified the accept/reject table) |
| Two-pass encode, not single-pass ABR | Single-pass `-b:v` drifts badly on mixed content (measured 7.18 Mbps actual on a 6 Mbps target, ~20% over); two-pass lands ~0.1–1% (5,992/6,000 kbps measured; 99.0–99.9% of target in ffmpeg-video-filesize's tests). The accuracy IS the feature | MEDIUM | Pass 1 = `-an -f null /dev/null` + `mktemp -d` passlogfile; verified end-to-end on n9.0.1 for both libx264 and libx265 |
| Audio carved out of the budget | Fixed audio (our 192k) is 1.4 MB/min — on a 10 MB target over a 5-min clip it eats 70% of the budget before video sees a bit. Every comparator subtracts audio first | LOW | `video_audio_kbps` already returns 192-or-0 — drop-in. Real design question is what happens when even audio doesn't fit (see below) |
| Container-overhead reserve | mp4 moov/mdat + faststart rewrite cost ~1–3%; budgeting every last bit to media overshoots. deepshrink reserves 2%, ffmpeg-video-filesize 2%, community guides ~2% | LOW | One constant in the awk math; combined with two-pass's natural slight-undershoot it lands "at or just under" — which is what a size target *should* mean |
| Honest refusal when infeasible | deepshrink exits 4 `Infeasible` below 60 kbps video; 8mb.video shows a 100 kbps-minimum error. Refusing beats encoding mush — and matches the milestone's own "honest refusal below every floor" | LOW | Needs a stated floor so the refusal can name the achievable minimum ("can't fit 10 MB into 12 minutes — ~18 MB minimum at this duration") |
| Resolution step-down on insufficient budget | Every serious comparator does this (deepshrink's ladder, shrinkwrap's 720p rescue, 8mb-compressor's thresholds). Bitrate starvation at high res looks *worse* than a smaller frame at the same budget | MEDIUM | Our ladder has 3 rungs (4k/1080p/720p) vs comparators' 5–6; floors need grounding (see Accuracy section). Below 720p floor → refuse, or extend the ladder — design call |
| Actual size reported at completion | Universal "before/after" reporting in compressors; already shipped (SIZE-02) | FREE | The notification becomes the promise-keeper: "Saved… (23 MB)" against a 25 MB target is self-verifying |
| Non-interactive + interactive parity | `discord-encode -size`, `deepshrink --target`, ffmpeg4discord `-s` — the flag is the primary interface everywhere; but the whole point of the menu row is reaching it without a terminal | LOW-MEDIUM | `--target` flag + "Custom size…" row → `omarchy-menu-input` (already shipped; zero QML work) |
| Mutual exclusivity with quality tier | `--target` sets bitrate; `[quality]` sets CRF — they're contradictory inputs | LOW | Reject `--target` + 4th-positional-quality together, early, before the start toast (v1.1 hoisted validation for exactly this reason) |

## Differentiators (worth doing, not required)

| Feature | Value proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| "Custom size…" as a 4th quality-menu row | No keyboard/menu comparator has this — the sharing-friendly answer ("fit under 10 MB") lives *inside* the same prompt as the tiers instead of a separate mode | LOW | `omarchy-menu-input` exists today; the row fits the `\tlabel\tsubtext` wire format; sentinel label hits `select_quality`'s re-validation chokepoint (STACK.md flags this is the *intended* interception point) |
| Effective-resolution honesty | When the budget forces 4k→720p, the done notification should name the *actual* output ("Transcoded to 720p mp4"), not the requested one. Comparators silently downscale; we already have the notification slot to say so | LOW | Falls out of passing the resolved (not requested) resolution to the toast — but it's a behavior nobody else bothers with |
| Step-down grounded in the existing ladder | Comparators keep encoding at 360p/240p/144p; a *sharing* tool can hold a higher dignity floor — refuse below 720p rather than ship a thumbnail. Opinionated restraint is on-brand | LOW | If dogfooding shows 720p-refusals on real targets, adding `scale=-2:480`/`-2:360` rungs is ~4 lines later — defer, don't design |
| One-shot overshoot correction | deepshrink corrects once; 8mb.local retries at >102%; ffmpeg4discord loops until under. A single "measure→adjust→re-encode" catches pathological overshoot without a convergence loop | MEDIUM-HIGH | A third pass's worth of encode time on the rare miss. **Recommend defer** — the 2% reserve + natural undershoot covers typical content, and the done notification reports the truth either way. Land it only if dogfooding produces real overshoots |
| Derived-plan transparency | deepshrink's `--dry-run` shows the plan before encoding. Our cheap equivalent: the start toast or the input-prompt echo can name the implied parameters ("10 MB over 3:12 → ~350 kbps → 720p") | LOW | Optional; honest-about-derivation is on-brand ("trade quality for size *knowingly*") but toast space is tight — design call |
| Intent presets ("for discord" → 10 MB) | 8mb.video's whole success is naming outcomes; `--for discord` is one word vs. remembering a number | LOW to ship, ONGOING to maintain | **Platform limits rot:** Discord went 8 MB → 25 MB → 10 MB in ~2 years (deepshrink ships a "verify against the current service" caveat for exactly this). A bare `10` is durable; `discord` needs a maintainer. If it ships, keep it a thin alias for a number — probably v1.x, not this milestone |

## Anti-Features (commonly requested, problematic here)

| Feature | Why requested | Why problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Guaranteed-byte promises ("always under N") | The Discord use case is literally "must not exceed" | Two-pass is typically ±1–3%, and pathological content (very short clips where fixed overhead dominates, multi-audio sources mis-budgeted) can overshoot. HandBrake *removed* target-size because "the error margin is too high" generated endless complaints — and theirs was single-pass, which is ~20% off, not our ~2%. The lesson isn't "don't do it," it's "don't claim a guarantee the math doesn't have" | Frame it as "aims at-or-under; typically lands within a few %"; the done notification reports actual. If a hard ceiling is ever needed, it's one correction pass — not a slogan |
| `-fs <bytes>` hard cap | Looks like a free guarantee | It *truncates the encode mid-stream* — produces a short, abruptly-ending file. An abort valve, not targeting. Verified anti-pattern in STACK.md | Two-pass + overhead reserve |
| Encode-until-converged retry loops | ffmpeg4discord/8mb.local do it; guarantees "under" | Each retry is a full extra pass (or two); on a laptop a 4k clip means 10+ minutes to chase 2%. A sharing tool's promise is "fast path to a file that fits," not "provably minimal" | 2% reserve + report actual; defer single-correction-pass |
| Resolution step-**up** / spending leftover budget on upscale | "Budget remains — why not 4k?" | Upscaling never adds information; it burns the user's budget on pixels the source didn't have. Current code *does* upscale (`scale=-2:2160` on a 1080p source); target mode should cap effective height at `min(requested, source)` — better use of every bit | Cap at source height in target mode |
| Codec selection under `--target` (VP9/AV1 for better bits-per-pixel) | "AV1 would fit 10 MB at better quality" | Decision paralysis in a quick-share flow; VP9/AV1 two-pass is dramatically slower; every codec needs its own floor table. The existing implicit x265-at-4k choice already encodes the project's opinionated-defaults contract | Keep the resolution-gated codec split exactly as-is |
| `--reduce <pct>` mode | deepshrink offers it | Answers a different question ("smaller" vs "under N") — nobody's upload limit is a percentage | Skip; if ever wanted it's `stat`-and-multiply over the same machinery |
| Remembering the last target / default target | "I always want 10 MB" | Silent state drift between runs; v1.1 already decided stateless is the contract | Repeat the flag; shell history exists |
| gif `--target` of any kind | Symmetry | **Verified:** gif encoder ignores `-b:v` entirely (byte-identical output at 100k vs 5000k — palette/fps/dither drive size, not rate control) | Refuse with an error, as specced; a sample-encode loop is deferred SIZE-12 territory |
| Audio drop / mute flag | Frees ~1.4 MB/min for video | Real feature (8mb-compressor has MUTE, deepshrink `AudioChoice::Drop`) but a second axis the one-flag feature doesn't need; refusal-with-explanation covers the pressure cases | Defer; if the refusal message says "minimum ~N MB *with audio*," the door stays open |

## How target-size actually works (the math every comparator shares)

```
usable_kbps  = target_bytes × 8 ÷ 1000 ÷ duration_s × (1 − 0.02)   # container reserve
video_kbps   = usable_kbps − audio_kbps                            # 192 or 0 today
```

Then: pick the highest resolution rung whose floor ≤ `video_kbps` (and ≤ requested, ≤ source); if `video_kbps` < every floor → refuse with the achievable minimum; else two-pass at `video_kbps`.

**Audio under pressure.** Today's fixed `-b:a 192k` breaks first on tight budgets — a 10-min clip at 10 MB has a *total* budget of ~137 kbps, less than the audio alone. Comparators solve this two ways: snap audio down a step ladder (deepshrink: 192→128→96→64… picking the highest step that still leaves ≥60k video) or expose it as a flag (ffmpeg4discord `-a 96`, shrinkwrap `MinAudioBitrate 64`). For this tool the honest minimal version is: try 192k; if it doesn't fit, step to ~96k then ~64k; if even 64k audio + minimum video exceeds the budget → refuse. Three constants in a `case`, not a new subsystem.

**Floor grounding.** Comparator floors for H.264-class content: deepshrink's ladder wants ≥2.5 Mbps for 1080p, ≥1.2 Mbps for 720p; 8mb-compressor keeps source res ≥900 kbps and drops to 480p below it; STACK.md's grounding is ~2 Mbps / ~800k / ~400k for 2160p/1080p/720p minimum-watchable. The spread is real (content-dependent — screencasts tolerate far less than action footage), so treat floors as heuristics with a refusal below the last rung, not physics. Recommended shape for our 3-rung ladder: derive `video_kbps` → step down while below the current rung's floor → refuse under ~400k at 720p.

## Accuracy — what two-pass can and cannot promise

Measured/observed across the comparators:

- **Typical case: lands ~1–3% under target.** Two-pass hits the *video stream* bitrate to ~0.1–1% (5,992 vs 6,000 kbps); add 2% container reserve and AAC's accurate CBR and the file lands just under nominal. STACK.md's empirical run: 241 KB actual vs ~260 KB nominal budget (~7% under on a 3 s clip — short clips under-run more because keyframe/overhead granularity dominates).
- **Single-pass is not a substitute:** ~20% drift on mixed content is what got HandBrake's target-size feature axed. If we don't two-pass, we don't have the feature.
- **Residual overshoot sources:** pathological content, very short durations (overhead granularity), sources whose audio was mis-detected. Rare, single-digit %, and always surfaced by the actual-size notification.
- **What it cannot promise:** "never exceeds N bytes." The honest contract is *aims at-or-under, typically lands within a few %, tells you the truth at the end* — which is sufficient for "will Discord take it" because platform limits have their own slack and the user sees the real number before uploading.
- **Hard dependency:** `video_duration` must succeed — no duration, no math. Probe failure → refuse honestly (never silently fall back to a CRF encode under a flag named `--target`).

## UX flow sketch

**Non-interactive:**
```
omarchy transcode --target 25M clip.mov mp4 1080p
omarchy transcode clip.mov mp4 720p --target 10M     # flag anywhere; parses like --path
```
Errors, all before any toast (v1.1 early-validation convention): `--target` on gif → refuse; on picture → refuse; with positional quality → conflict error; unparseable size → usage error; undetectable duration → honest refusal; budget under every floor → refusal naming the achievable minimum.

**Interactive (mp4 path):**
```
file → format(mp4) → resolution → Select quality:
   high     CRF 18 · ~42 MB
   medium   CRF 23 · ~24 MB        ← Enter lands here (unchanged)
   low      CRF 28 · ~9 MB
   Custom size…   fit under a target   → omarchy-menu-input "Target size (e.g. 25M)"
```
Picking the row summons `omarchy-menu-input`; the typed text goes through the same parser as `--target` (one parser, one validation path). Esc at input = abort like every other prompt; empty submit returns exit-0-with-empty (STACK.md quirk) — treat as invalid input, not cancel. Re-prompt once on garbage vs error-out: design call, lean re-prompt (the user is already mid-gesture).

**Notifications:** start toast unchanged in shape ("clip.mov to mp4 (1080p)" — or name the target: "…(1080p, ≤25M)"); done toast already reports actual size — the only honesty-critical tweak is that the resolution it names must be the *effective* one after step-down.

**Naming:** `stem-1080p-25M.mp4` — pass the normalized target through `output_path`'s 4th arg; self-documenting and collision-free vs. tier-named outputs.

## Dependencies on shipped v1.1 work

| v1.1 piece | What `--target` reuses |
|------------|------------------------|
| `video_duration` (:162) | The whole budget formula's denominator — probe-failure → refuse, mirroring `estimate_label`'s honesty convention |
| `video_audio_kbps` (:172) | The audio carve-out, already 192-or-0 conservative |
| `estimate_label`'s awk+MiB convention | Same float-math style; target parse should land on the same MiB-labeled-MB scale the notification reports |
| `output_path` 4th arg + dedupe | Target string becomes the filename suffix; `[[ -e || -L ]]` dedupe already prevents the overwrite-prompt hang |
| `select_quality` wire format + strip-at-first-tab re-validation | "Custom size…" is a 4th `\tlabel\tsubtext` row; the re-validation case is the intended interception point for the sentinel |
| `omarchy-menu-input` | Shipped today — `mode:"input"` needs zero Menu.qml/menu-select changes |
| Actual-size completion notification (SIZE-02) | Becomes the promise-verification step for free |
| Early validation hoisting (v1.1 close) | `--target` format/gif/picture/quality-conflict checks belong in the same pre-menu, pre-toast block |
| `transcode-quality-test.sh` argv-stub harness | Two-pass = two recorded invocations (`-pass 1`, `-pass 2`); extend the stub, no new harness |

## In this milestone vs. deferred

**In (per PROJECT.md goal + this research):**
- `--target <size>` flag (mp4 only): parse/normalize/validate early; two-pass with overhead reserve and audio carve-out
- Resolution auto-step-down within the 3-rung ladder + refusal below the 720p floor (floor values are a plan-level pick — grounding above)
- Audio step-down (192→96→64k) or refuse-instead — must be decided; without it, tight-but-legit targets refuse prematurely
- "Custom size…" quality-menu row → `omarchy-menu-input` → shared parser
- gif/picture refusal; `--target`×quality mutual exclusion; effective-resolution in done toast; `stem-res-NM` naming

**Deferred (tracked):**
- One-shot overshoot correction — land only if dogfooding shows real overshoots
- Intent presets / `--for discord` — needs a maintainer-owned limits table; thin-sugar over `--target`, fine as v1.x
- Lower rungs (480p/360p) — add only if refusal bites in practice
- Audio drop/mute flag; `--reduce %`; gif target (SIZE-12 adjacent); VMAF search (deepshrink territory — not ours)

## Competitor Feature Analysis

| Capability | HandBrake | Discord-ecosystem CLIs | 8mb.video/.local | deepshrink | Our approach |
|-----------|-----------|------------------------|------------------|------------|--------------|
| Size model | Removed target-size; CRF or avg-bitrate+2pass | `-size`/`-s`/`--target` flag | Web preset buttons + custom | `--target`/`--reduce`/`--for`/`--dry-run` | `--target <size>` flag + "Custom size…" row |
| Passes | 2-pass optional (turbo first pass) | 2-pass standard | 2-pass + auto-retry >102% | 2-pass + one correction | 2-pass, accept tolerance, report actual |
| Audio | User-set | Fixed/configurable (96k/128k) | ~10% of budget | Step-ladder fit (≥60k video floor) | 192k→96→64 step-down or refuse |
| Resolution | User-set | `-r` explicit, or fixed thresholds | Auto | Ladder to 144p | Step down within 4k/1080p/720p, refuse below |
| Infeasible | n/a | Encode anyway / min-bitrate dialog | 100k error + "Encode Anyway" | `Infeasible` exit 4 | Refuse naming the achievable minimum |
| Undershoot policy | n/a | Loop until under (optional `--approx`) | Auto-retry | Correct once | Report actual; no chase |
| Guarantee language | Refused the feature over accuracy | "smash into 25MB" | "exact file sizes" | "lands under" | "aims at-or-under; reports actual" |

## Sources

- **Repo (read in full this session):** `bin/omarchy-transcode` (arg loop :305-331, helpers :162-299, `select_quality` :247-287, `output_path` :49-73), `bin/omarchy-menu-select` (`--` arg boundary, tab⇥subtext contract), `bin/omarchy-menu-input` (input-mode wrapper), `shell/plugins/menu/Menu.qml` (input routing :27/:558-561/:765-767, submit-is-filterText :1160), `.planning/PROJECT.md` v1.2 goal, `.planning/milestones/v1.1-REQUIREMENTS.md` SIZE-10/11/12 deferral notes, `.planning/research/STACK.md` (v1.2 — two-pass verified on n9.0.1, gif `-b:v` invariance, `-fs` anti-pattern, passlogfile conventions)
- **Comparator docs/source:** aWZHY0yQH81uOYvH/discord-encode (two-pass ABR, `-size`, 10 Mbps cap); nunogomes255/ffmpeg-shrinkwrap (waterfall: retry → 720p rescue at 500k floor → CRF 28 → split); zfleeman/ffmpeg4discord (two-pass loop until under, `--approx`, `-a 96`); crusader290/8mb-Video-Compressor (resolution thresholds 900k/400k, `-fs` cap, 128k audio); deeplabua/deepshrink `budget.rs` (CONTAINER_OVERHEAD 0.02, ABSOLUTE_MIN_VIDEO_BPS 60k, rung ladder 1080p≥2.5M→144p≥100k, AUDIO_STEPS, `fit_audio_bps`, `Infeasible`); 8mb.video releases (100 kbps minimum dialog); 8mb.local coverage (retry at >102%, 8/25/50/100 + custom UX)
- **Accuracy evidence:** Martin Riedl two-pass walkthrough (single-pass 7.18M vs 6M target ≈ 20% over; two-pass 5,992k ≈ 0.13% under); andreswatson/ffmpeg-video-filesize (2% margin → 99.0–99.9% of target; GPU encoder overshot 26.29/25); ffmpeg-cookbook two-pass article (`total = MB×8192/dur` formula, `-passlogfile` collision warning, `-an`+`-f null` pass 1)
- **HandBrake:** GitHub issues #4640/#4622/#1958 + docs — target-size removed for accuracy-driven support burden ("error margin too high… never ending complaints"); recommends against size targeting, prefers CRF
- **Platform limits:** Discord support docs (free 10 MB, Basic 50 MB, Nitro 500 MB, boosted-server 50/100 MB; 8→25→10 MB history = preset-rot evidence); deepshrink preset table (whatsapp 16 MB, email 20 MB, telegram 2 GB)

---
*Feature research for: omarchy-transcode `--target <size>` two-pass mode + Custom size menu row (v1.2)*
*Researched: 2026-09-16*
