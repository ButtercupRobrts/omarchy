# Project Research Summary

**Project:** Omarchy fork — milestone v1.1 "Transcode Quality & Size Feedback"
**Domain:** CLI media transcoding UX — bash script + ffmpeg/ImageMagick + Quickshell/QML dmenu
**Researched:** 2026-09-15
**Confidence:** HIGH (all touch points read end-to-end; CRF tier values grounded in encoder-community consensus; bitrate midpoints MEDIUM — CRF output legitimately varies ±2× with content, which is inherent, not a research gap)

## Executive Summary

This milestone adds a quality step to `bin/omarchy-transcode`: three named tiers (high/medium/low) mapped to CRF values for mp4 and fps values for gif, an "~N MB" size estimate as subtext on each quality row, a pre-highlighted `medium` Enter-default, and the actual output size in the completion notification. The product sits in the constant-quality (CRF) tradition — HandBrake-style — where the user picks quality and size is an approximate consequence. The alternative target-size model (8mb.video, discord-encode: "fit under N MB" guaranteed by two-pass encoding) is deliberately deferred to v2 because it doubles encode time and contradicts the fast default path.

The recommended implementation needs **zero new dependencies**: ffmpeg/libx264/libx265, ffprobe, ImageMagick, `numfmt`, `stat`, and `awk` are all in the Omarchy default package set. The work lands in exactly three files — `bin/omarchy-transcode` (new `quality` positional + prompt + estimate helpers), `bin/omarchy-menu-select` (new `--default-index` flag after `--`, plumbed into the perl `JSON::PP` payload), and `shell/plugins/menu/Menu.qml` (`openDmenu` applies `payload.defaultIndex` to `selectedIndex`). Non-interactive callers (Nautilus extension, scripts) are unaffected: an omitted/`medium` quality reproduces today's encoder flags and filename byte-for-byte.

The main risks are protocol-shaped, not algorithmic: (1) menu subtext is returned to the caller tab-joined and must be stripped before `case` matching; (2) `defaultIndex` must be a post-`--` flag — anything positional/leading silently corrupts the five stdin-fed menu callers; (3) ffmpeg's overwrite prompt hangs or silently kills the script depending on launch path, so an explicit collision policy must be decided with the new suffix scheme; (4) "high/medium/low" already means *resolution* for pictures in positional slot 3, so a 4th positional on a picture must be rejected, not ignored. CRF estimate precision is the other known trap: table midpoints can be off ±2× on edge content, so estimates are rounded, `~`-prefixed, and the actual size is reported at completion to close the calibration loop.

## Key Findings

### Recommended Stack

No new dependencies. The existing toolchain covers everything; awk is the repo's established float-math convention (`omarchy-hyprland-monitor-scaling`, `omarchy-network-speedtest`).

**Core technologies:**

- ffmpeg + libx264 (720p/1080p, `-preset fast` fixed) and libx265 (2160p only, `-preset slow` fixed): CRF mode holds *perceptual quality* constant and lets bitrate float — the right primitive for a quality picker; a `-b:v` bitrate tier would punish complex content and waste bits on simple content
- ffprobe (`-show_entries format=duration`): instant container-header parse for the estimate formula — nothing cheaper exists without decoding
- `numfmt --to=iec` + `stat -c %s` (coreutils): humanize estimated and actual byte counts
- awk: float math for `duration × bitrate` — bash has no floats; `bc` is not guaranteed installed
- ImageMagick: picture path unchanged — pictures get no quality step (TRANSC-06)

**Locked quality tiers** (medium = today's exact flags, TRANSC-02; presets stay fixed per tier):

| Codec / scope | high | medium (locked) | low |
|---|---|---|---|
| x264 (720p, 1080p) — `-preset fast` | CRF 18 (~1.8× size) | CRF 23 (1×) | CRF 28 (~0.45×) |
| x265 (2160p only) — `-preset slow` | CRF 20 (~1.6×) | CRF 24 (1×) | CRF 28 (~0.5×) |
| gif — fps tier | 15 fps (~1.5×) | 10 fps (1×, current) | 5 fps (~0.5×; 8 fps is the gentler fallback) |

x265 CRF ≈ x264 CRF + ~5 for perceptual parity — never copy a CRF number across codecs. Each ±6 CRF steps ≈ halves/doubles x264 bitrate (~5.3 for x265), so the tiers give a meaningful ~2× spread each direction. `preset` is deliberately *not* varied per tier: it trades encode time for size-efficiency, not user-visible quality, and varying it blurs the "medium = today's flags" contract. (Architecture doc's inline suggestion of x264 19/28 and x265 21/29 is superseded by these locked STACK values.)

**Bitrate estimate table** (video kbps midpoints for typical mixed content; ±2× real variance):

| Resolution | Codec / CRF tiers | high | medium | low |
|---|---|---|---|---|
| 720p | x264 18/23/28 | 2.5 Mbps | 1.5 Mbps | 0.7 Mbps |
| 1080p | x264 18/23/28 | 5.5 Mbps | 3.0 Mbps | 1.4 Mbps |
| 2160p | x265 20/24/28 | 16 Mbps | 9 Mbps | 4.5 Mbps |

Formula: `est_bytes = dur_s × (video_kbps + 192) / 8` via awk — **include the 192k AAC audio term** (~1.4 MB/min; at low/720p it's ~25% of output). Display `~`-prefixed, 1–2 sig figs. GIF estimates are omitted entirely — gif size is content-dominated with a 20–30× spread; use fps as the subtext instead. If ffprobe returns `N/A`, fall back to no-number subtexts ("Best quality" / "Smallest file") — a missing estimate beats a wrong one.

### Expected Features

**Must have (table stakes):**

- Named quality tiers (high/medium/low) — every consumer flow uses plain language; raw CRF numbers stay internal
- Pre-selected sane default — `medium` pre-highlighted so Enter = today's behavior (TRANSC-05)
- Size signal before committing — "~N MB" subtext per quality row (TRANSC-03); users universally ask "how big will it be?"
- Actual output size at completion — closes the estimate→reality loop (TRANSC-04)
- Non-interactive parity — 4th positional arg; omitted/`medium` is byte-identical to current flags (TRANSC-02)
- Honest approximation — `~` prefix, aggressive rounding, never "14.2 MB"
- Pictures skip the step entirely; quality suffix only when non-default (TRANSC-06)

**Should have (differentiators in this milestone):**

- Per-option size estimate as subtext — almost no keyboard/menu tool does this; feasible because resolution is already chosen
- Estimate→actual feedback loop in the notification — no comparator shows both; calibrates user trust over time
- Same high/medium/low vocabulary for gif (fps tiers) — coherent UX across formats (TRANSC-01)

**Defer (v2+):**

- **Target-size two-pass mode** (`--target 8MB`) — the only way to make "fits X" a promise; ~2× encode time and a parallel code path. Compute `b:v = (target_bits − 192k×dur) / dur`, two passes with `-an`+null-muxer pass 1
- **Intent presets** ("discord" → fits 10 MB) — a promise about bytes that CRF can't honestly make; requires target-size mode underneath
- gif estimate subtext — needs its own fps/area-scaled table if ever wanted (720p ≈ 0.4 MB/s, 1080p ≈ 0.9 MB/s, 2160p ≈ 2.5 MB/s, labeled "varies widely")
- Audio-quality tier / mute option; batch-quality-remembering in the Nautilus multi-file loop

**Anti-features to avoid:** bitrate slider / raw CRF entry (logarithmic, codec-literacy required), codec sprawl (keep implicit x265-at-4k), fake-precision estimates, sample-encode preview, estimates on the resolution step (would need an assumed quality → dishonest or uselessly wide range), guaranteed size claims without two-pass, remember-last-quality sticky defaults.

### Architecture Approach

Three entry points (menu `trigger.transcode`, Hyprland binding, Nautilus `transcode.py`) all invoke `bin/omarchy-transcode`, which prompts through `bin/omarchy-menu-select` → `omarchy-shell` → `qs ipc` → `Menu.qml openDmenu(payload)` → tempfile handshake returning the selection. Changes land in three files:

**Major components:**

1. `bin/omarchy-transcode` (207 lines) — metadata/`usage()` gain `[quality]`; `output_path()` gains 4th param emitting `stem-resolution-quality.format` only when quality ≠ `medium`; `transcode_video()` gains quality-mapped flag arms (medium = today's literals); new `video_duration()` (ffprobe), `video_bitrate_kbps()` (nested case table), `estimated_size()` (awk + numfmt); `main()` gains `quality="${positional[3]:-}"` and a video-only prompt block placed **after** format+resolution (estimates key on both); completion notification appends actual size via `stat`/`numfmt`
2. `bin/omarchy-menu-select` (99 lines) — new `--default-index N` arm in the post-`--` flag loop (mirroring `--width`); perl `JSON::PP` payload gains `defaultIndex` as an optional int (field absent when flag omitted → full back-compat for all 16 callers); `docs/menu.md` updated
3. `shell/plugins/menu/Menu.qml` + `MenuModel.js` — `dmenuDefaultIndex` property, `selectedIndex = dmenuDefaultIndex` in `openDmenu` (line 874); the existing clamp in `rebuildDmenuDisplay` (596–598) makes out-of-range values safe; put the payload→index resolution in `MenuModel.js` so `menu-test.sh`'s node harness can cover it. `transcode.py` needs no change

**Two row/return contracts the caller must honor:**

- Row construction: when an option contains a tab, the **first** field is consumed as glyph/icon (Menu.qml:568–571) — a no-icon `label + subtext` row must be sent as `"\tlabel\tsubtext"` (leading empty field), or "high" renders as an icon and the estimate becomes the label
- Return value: `activateIndex` (768) writes `label<TAB>detail` — the caller must strip: `quality="${selection%%$'\t'*}"` (precedent: `omarchy-menu-plugin` uses `cut` for this)

**Build order:** (1) menu `defaultIndex` plumbing — self-contained, node-testable; (2) non-interactive quality arg + flag tables + suffix — testable with zero menu involvement; (3) interactive prompt + estimates; (4) notification size; (5) docs/metadata. Steps 1–2 are independent atomic commits per Omarchy convention.

**Upstream interaction:** open PR #6698 (folder transcoding) conflicts textually in `main()`'s tail, `output_path`'s signature, and the new-function insertion region; name the new test `test/shell.d/transcode-quality-test.sh` (not `transcode-test.sh`, which the PR creates). Our optional-4th-arg design keeps their call sites working; whichever merges second handles batch-quality amortization.

### Critical Pitfalls

1. **Menu subtext is returned to the caller** — `"low\t~9MB"` breaks `case` matching and exits 1, silently when detached. Strip at first tab immediately: `quality=${quality%%$'\t'*}`. Every new subtext menu call needs this.
2. **`defaultIndex` must be a `--` arg, never positional** — `omarchy-menu-select` treats every token before `--` as a menu row and reads options from stdin when none are given; a leading arg corrupts all 16 callers including the five stdin-fed ones. Implement as `-- --default-index 1` alongside `--width`/`--maxheight`.
3. **ffmpeg overwrite behavior differs by launch path** — no `-y`/`-n` means "Overwrite?" prompt: hangs in the Nautilus terminal (tty), reads EOF + dies under `set -e` when detached (start notification sent, completion never arrives). Decide an explicit collision policy (dedupe `foo-1080p-2.mp4`, or deliberate `-n`) **before** the "Transcoding…" notification; blanket `-y` is a data-loss trap. ImageMagick silently overwrites — behavior is already inconsistent.
4. **Vocabulary collision: high/medium/low is already picture *resolution* in slot 3** — `omarchy transcode pic.png jpg low` means low-res today; `... jpg medium high` must error clearly ("quality applies to video only"), not silently ignore. Sync `usage()`, `# omarchy:args=`/`examples=`, `capture.md` skill doc, and `manual/12-screenshots-recording.md` in the same commit — `test/cli` checks metadata shape.
5. **Probe/math failures abort silently under `set -euo pipefail`** — ffprobe can return `N/A` or fail on odd files; in command substitution the script dies before the menu opens, with stderr going nowhere when detached. Guard every probe: `$(ffprobe ... 2>/dev/null || true)` + `[[ $x =~ ^[0-9.]+$ ]]`, fall back to plain-label rows. Remember `(( expr ))` returns status 1 when the result is 0.
6. **x265 ≠ x264 CRF semantics** — applying one CRF table to both codecs makes "medium" differ visibly between 1080p and 4k; the per-codec locked tables above exist precisely for this. Verify medium diffs clean vs current flags on *both* codec paths.
7. **Estimate honesty** — content variance (±2×) exceeds tier spacing on edge content; an already-efficient source re-encoded at "high" can come out *larger* than input. Round to 1–2 sig figs with `~`, optionally compare against source size ("may be larger than original"), and let TRANSC-04's actual-size report absorb the error.

Also watch: subtext ≤ ~30 chars and tab-free (it's display + filter corpus + return key on a ~300px card; mixing subtext/no-subtext rows produces uneven heights — give all three quality rows subtexts or none); `setFilter` resets `selectedIndex` to 0 on first keystroke (correct — defaultIndex is initial-only; comment it so nobody "fixes" it); ffprobe only inside the interactive video branch so non-interactive calls never pay for it.

## Implications for Roadmap

Suggested phase structure (maps to atomic commits; v1.1 phases not yet written into ROADMAP.md):

### Phase 1: Menu `defaultIndex` plumbing (TRANSC-05)

**Rationale:** Self-contained, additive, and unblocks the "Enter = medium" contract; every existing caller unaffected because the payload field is simply absent. Putting it first lets the transcode work assume the flag exists.
**Delivers:** `--default-index` flag in `omarchy-menu-select`, `defaultIndex` JSON payload field, `dmenuDefaultIndex` property + `selectedIndex` init in `Menu.qml`/`MenuModel.js`, `docs/menu.md` update.
**Avoids:** Pitfall 2 (positional arg corrupts stdin-fed callers); out-of-range safety via existing clamp.
**Tests:** node-testable via `menu-test.sh` `run_node_test` + payload-capture `omarchy-shell` stub; verify all 16 callers still work, especially stdin-fed ones.

### Phase 2: Non-interactive quality in `omarchy-transcode` (TRANSC-01/02/06 core)

**Rationale:** Testable with zero menu involvement; establishes the locked flag tables and the byte-identical-medium contract before any UI depends on it.
**Delivers:** 4th positional arg with validation (picture + 4th arg errors); per-codec CRF/fps tier tables; `output_path` quality suffix (non-default only); explicit output-collision policy; `usage()`/`# omarchy:*` metadata/docs sync.
**Avoids:** Pitfalls 4 (overwrite), 6 (cross-codec CRF), 7 (vocabulary collision).
**Tests:** stub ffmpeg/magick to record args; diff `mp4 1080p medium` and omitted-quality invocations against today's exact flags and filename.

### Phase 3: Interactive quality prompt + size estimates (TRANSC-01/03)

**Rationale:** Depends on both prior phases (needs the flag tables from Phase 2 and `--default-index` from Phase 1); must come after format+resolution prompts since estimates key on all three.
**Delivers:** `video_duration()`/`video_bitrate_kbps()`/`estimated_size()` helpers; `"\tlabel\tsubtext"` row construction; `omarchy-menu-select … -- --default-index 1`; `%%$'\t'*` strip; guarded-probe fallbacks; gif rows with fps subtext.
**Avoids:** Pitfalls 1 (subtext return), 3 (fake precision — `~` prefix, audio term included), 5 (audio floor), 8 (set -e probe abort), 10 (subtext width/protocol).
**Tests:** `test/shell.d/transcode-quality-test.sh` (stub ffprobe, menu-select, ffmpeg); captured rows contain tab-joined estimates; `N/A` duration still opens the menu; visual verification of the quality card at runtime.

### Phase 4: Completion-size notification + docs (TRANSC-04)

**Rationale:** Cheap tail-end change that closes the estimate→actual loop; keeps the notification edit in its own atomic commit.
**Delivers:** `stat`/`numfmt` actual size appended to the existing completion notification; final docs sweep.
**Avoids:** "looks done but isn't" gaps (docs/metadata sync, visual check).

### Phase Ordering Rationale

- Menu plumbing first because it's the only cross-component contract change and is independently revertible (additive `--` arg)
- Non-interactive quality before interactive so the flag tables and the TRANSC-02 invariant are proven before subtext parsing adds a failure mode
- Estimates last among features because they need *all* inputs (format × resolution × quality) and both prior phases
- Grouping matches Omarchy's atomic-commit convention — each phase is one reviewable change, and Phases 1–2 could land in either order

### Research Flags

Phases likely needing deeper research during planning:

- **Phase 3:** Estimate accuracy validation requires dogfooding (transcode 3 varied clips, compare estimate vs actual); the clamp-against-source-size refinement and gif subtext wording need a design call. Subtext elision at ~300px needs running-UI verification.
- **Phase 2:** The collision-policy decision (dedupe vs `-n` vs `-y`) is a product call, not a technical one — decide before implementation.

Phases with standard patterns (skip research-phase):

- **Phase 1:** Exact precedent exists (`--width`/`--maxHeight` plumbing); fully specified
- **Phase 4:** One-line `stat`/`numfmt` addition to an existing notification

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | CRF tiers, fps-as-lever, and ffprobe estimation verified against encoder-community consensus and repo conventions; no new deps |
| Features | HIGH on comparator behavior, MEDIUM on transferability | CRF-model choice validated for a quick-share flow; keyboard-menu estimate subtext is a differentiator without direct precedent |
| Architecture | HIGH | All three target files read end-to-end; line numbers verified; upstream PR #6698 diff reviewed; row/return contracts confirmed in source |
| Pitfalls | HIGH | Source-verified against the three target files and all 16 `omarchy-menu-select` call sites; subtext-return and stdin-collision pitfalls are mechanical, not speculative |

**Overall confidence:** HIGH

### Gaps to Address

- **Bitrate midpoint variance (MEDIUM):** the estimate table can be ±2× off on edge content — inherent to CRF. Handle via `~` labeling, 1–2 sig figs, optional source-size sanity check, and the TRANSC-04 actual-size report. Dogfood-validate the table on 3 varied clips during Phase 3.
- **Collision policy undecided:** dedupe vs `-n` vs `-y` must be chosen deliberately in Phase 2 — never blanket `-y`.
- **gif low-tier value:** 5 fps locked, but 8 fps documented as the gentler fallback if dogfooding finds 5 too choppy.
- **PR #6698 timing:** whichever side lands second rebases `main()`'s tail and `output_path`'s signature; test-file name collision already avoided by using `transcode-quality-test.sh`.
- **Picture + 4th-positional behavior:** reject-with-error recommended over ignore — confirm at requirements/implementation time and test it.

## Sources

### Primary (HIGH confidence)

- Repo reads in full: `bin/omarchy-transcode` (207 lines), `bin/omarchy-menu-select` (99 lines), `shell/plugins/menu/Menu.qml` (1480 lines — `openDmenu` 861–881, `rebuildDmenuDisplay` 553–603, `activateIndex` 759–787), `bin/omarchy-menu-plugin` (cut precedent), `default/nautilus-python/extensions/transcode.py`, `default/omarchy/omarchy-menu.jsonc:69`, `test/shell.d/*-test.sh` conventions, `test/cli` metadata assertions
- ffmpeg-micro.com CRF guide + FFmpeg wiki — x264 sane range 18–28, ±6 ≈ half/double bitrate, x265 default 28 ≈ x264 23
- HandBrake docs — constant-quality vs ABR ("output size is unpredictable"), preset model
- Upstream diff `github.com/omacom/omarchy/pull/6698.diff` — conflict sites identified
- `.planning/PROJECT.md` TRANSC-01..06, `.planning/REQUIREMENTS.md`

### Secondary (MEDIUM confidence)

- video.stackexchange #16664 + Doom9 — x265↔x264 CRF perceptual mapping (+~5)
- Gough's Tech Zone CRF curves — measured ~6.05 (x264) / ~5.34 (x265) steps per 2× bitrate
- GitHub CLI wrappers — discord-encode (`-size`, two-pass), deepshrink (`--target`), ffmpeg-shrinkwrap — target-size model shape for v2
- vibbit.ai/browsercut.com — real-world CRF 23 size ranges and content-variance magnitude

### Tertiary (LOW confidence)

- Mobile compressor apps (Video Compressor HD, video_compress_kit `estimateFileSize`) — live-estimate UX precedent; transferability to a menu is inferred
- gif MB/s-per-resolution baselines (0.4/0.9/2.5 MB/s) — coarse, only if gif estimates are ever attempted

---
*Research completed: 2026-09-15*
*Ready for roadmap: yes*
