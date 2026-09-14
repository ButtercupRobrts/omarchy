# Pitfalls Research

**Domain:** Shell-script media transcoding UX — adding quality tiers, size estimates, and a menu default-index to `bin/omarchy-transcode`, `bin/omarchy-menu-select`, and `shell/plugins/menu/Menu.qml`
**Researched:** 2026-09-15
**Confidence:** HIGH (source-verified against the three target files and all 16 `omarchy-menu-select` call sites in `bin/`)

## Critical Pitfalls

### Pitfall 1: Menu subtext is returned to the caller, breaking `case` matching

**What goes wrong:**
The quality menu rows carry an estimate as subtext (`"High\t~120 MB"`). `Menu.qml` (`activateIndex`, line 768) returns `picked.label + "\t" + picked.detail` when a row has detail, so `quality=$(omarchy-menu-select ...)` captures `High<TAB>~120 MB`, not `High`. The subsequent `case "$quality" in high|medium|low)` falls through to the invalid branch and the script exits 1 — silently when launched detached from the menu trigger or keybinding.

**Why it happens:**
The subtext feature was designed so same-named rows return a stable key (documented in `bin/omarchy-menu-select` lines 9–13), so the tab-suffixed return is intentional and global. Every existing caller gets plain labels back only because none of them use subtexts yet. It is easy to test the menu visually (it looks right) and never test what the variable contains.

**How to avoid:**
Immediately after capturing, strip at the first tab: `quality=${quality%%$'\t'*}`. Alternatively have the caller pass an explicit value column — but the simplest fix is documenting that subtext is display-only data that must be cut before use. Do this for every new menu call that uses subtext (quality rows; gif rows if they get fps subtexts).

**Warning signs:**
- Transcode exits with "Invalid ... quality" (or nothing at all) right after the menu closes
- Works when quality is passed positionally but not interactively (or vice versa)
- `omarchy-menu-plugin` (line 33) already relies on multi-field returns — it is the model to copy

**Phase to address:**
Implementation phase covering TRANSC-01/TRANSC-03 (the first commit that adds subtext to any menu call in `omarchy-transcode`)

---

### Pitfall 2: `defaultIndex` implemented as a positional/leading arg breaks all 16 callers

**What goes wrong:**
`bin/omarchy-menu-select` parses `$1` as the prompt, then collects *every* remaining token as an option until a literal `--` (lines 29–59). Any flag-shaped token before `--` becomes a menu row. Worse, when zero positional options are given it reads options from stdin (`mapfile -t options`, lines 61–63) — so a signature like `omarchy-menu-select <prompt> <default-index> [option...]` silently corrupts piped callers (`omarchy-menu-timezone`, `omarchy-menu-keybindings`, `omarchy-menu-plugin`, both keybinding-list menus) by shifting "default-index" into their option stream.

**Why it happens:**
The script has two option sources (argv and stdin) and no flag namespace before `--`. A "just add a parameter" change looks natural but collides with both.

**How to avoid:**
Add `defaultIndex` as a menu arg *after* `--`, alongside `--width`/`--maxheight` (e.g. `-- --default-index 1`), parse it into the JSON payload, and have `Menu.qml` `openDmenu` (line 861) apply `payload.defaultIndex` to `selectedIndex` before `rebuildDisplay()`. `omarchy-menu-file` (line 48) already forwards caller `"$@"` after `--`, so the arg propagates through wrappers for free. Clamp in QML: `rebuildDmenuDisplay` (lines 596–598) already clamps `selectedIndex` to the filtered count, so out-of-range values degrade safely if set before the rebuild.

**Warning signs:**
- Menus elsewhere suddenly showing rows like "1" or "--default-index"
- Timezone/keybinding menus losing their first entry
- Tests that stub `omarchy-menu-select` (e.g. `test/shell.d/menu-plugin-test.sh`) still pass while real callers break

**Phase to address:**
Implementation phase covering TRANSC-05 (menu plumbing) — must be decided before `omarchy-transcode` depends on it

---

### Pitfall 3: CRF is content-variable — single-number estimates are fake precision that will embarrass

**What goes wrong:**
The estimate table is `ffprobe duration × bitrate-per-tier` (per PROJECT.md). CRF mode picks bitrate by content complexity: the same CRF 23 yields ~2 Mbps on a clean screencast and ~15 Mbps on noisy handheld footage at 1080p. A subtext saying "~45 MB" is wrong by 3–5× on real inputs. Worst case: re-encoding an already-efficient file at "high" produces output *larger* than the input, and the estimate said it would shrink.

**Why it happens:**
Duration × bitrate feels like the honest way to estimate, but the bitrate is the unknown. Content variance is the dominant error term, larger than the tier spacing itself on edge content.

**How to avoid:**
- Round aggressively: one significant figure or a small range ("~40 MB", not "~43.7 MB"), and prefix with `~` or "≈"
- Key the table by codec *and* resolution (x265 at 4k vs x264 at 720p differ by ~10×)
- Sanity-clamp against the source: `stat -c %s` input size ÷ duration gives the source bitrate; if a tier's assumed bitrate implies output > input, say so ("may be larger than original") or widen the range
- For gif, do not show size estimates at all (TRANSC-03 already scopes estimates to mp4) — use the fps value as the subtext instead; gif size is dominated by palette/dither interactions no table predicts

**Warning signs:**
- Dogfooding: transcode 3 different clips and compare estimate vs actual; >2× error on any is the smell
- Estimates that print identical MB for 720p and 4k rows
- Any estimate displayed with more than 2 significant digits

**Phase to address:**
Implementation phase covering TRANSC-03; the clamp-against-source check can ship in the same commit cheaply

---

### Pitfall 4: ffmpeg overwrite behavior differs by launch path — hang in terminal, silent failure detached

**What goes wrong:**
`output_path` is deterministic: `stem-resolution.format` (line 56), gaining a quality suffix only for non-default quality (TRANSC-06). Re-transcoding the same file at the same tier collides. ffmpeg without `-y`/`-n` prompts "Overwrite? [y/N]" on stdin. In the Nautilus path the floating terminal gives it a tty — the script appears to hang mid-encode. Via the menu trigger (`Util.execDetached`, `Menu.qml` line 141) there is no tty; ffmpeg reads EOF, refuses, and exits nonzero — `set -euo pipefail` then kills the script *after* the "Transcoding video…" notification but *before* the completion one: the user sees a start and no end. ImageMagick, by contrast, silently overwrites — pictures and videos get inconsistent collision behavior today.

**Why it happens:**
The script is invoked from three environments with different stdin/tty semantics (menu keybind = detached, Nautilus = presentation terminal, direct CLI = user's shell), and `set -e` turns ffmpeg's "polite refusal" into an invisible abort.

**How to avoid:**
Pick one policy and make it explicit. Reasonable: pre-check `[[ -e $output ]]` and dedupe (`foo-1080p-2.mp4`) or pass `-n`/`ask` deliberately; do NOT blanket `-y` without deciding, since silent clobber is also a data-loss trap. Whatever is chosen, handle the collision *before* sending the "Transcoding…" notification so failure states are never orphaned.

**Warning signs:**
- Second transcode of the same file "does nothing" from the keybinding
- ffmpeg sits at 0% in the floating terminal waiting for input
- `foo-1080p.mp4` already exists in the target dir during manual testing

**Phase to address:**
Implementation phase covering TRANSC-01 — it is one `[[ -e ]]` branch and must land with the new suffix scheme

---

### Pitfall 5: Audio floor and no-audio sources break the bitrate table at the low end

**What goes wrong:**
`-c:a aac -b:a 192k` is fixed regardless of tier. 192 kbps ≈ 1.4 MB/min. On a 15-second 720p/low clip the video may be ~1 MB while audio is ~0.4 MB — a large fraction the estimate ignores if the table is video-only. Conversely, a silent screen recording has no audio stream at all (`-c:a` is ignored), so a table that bakes in 192k overshoots. Also: scaling *up* happens today (`scale=-2:2160` upscales a 1080p source when "4k" is picked), so "4k high" on small input produces a large file with zero quality gain — estimates must assume the post-scale bitrate, and arguably the menu should warn.

**Why it happens:**
Estimate models naturally focus on the video stream; audio is a constant additive term that only matters proportionally at low tiers/short durations — exactly the rows users pick to save space.

**How to avoid:**
Include `+ 192k × duration` (or the tier's audio rate) in every mp4 estimate. Cheap improvement: `ffprobe -show_entries stream=codec_type` once and drop the audio term when no `audio` stream exists. Consider whether the "low" tier should also lower `-b:a` (e.g. 96k) — if it does, the table must track it.

**Warning signs:**
- Short clips consistently finish ~0.4 MB/min above or below estimate
- Silent screencasts always under the estimate by a fixed per-minute offset

**Phase to address:**
Implementation phase covering TRANSC-03

---

### Pitfall 6: x265 and x264 CRF values are not perceptually equivalent — copy-pasting CRF tiers across codecs shifts quality

**What goes wrong:**
The existing code already encodes this trap: 4k uses `libx265 -crf 24 -preset slow`, 1080p/720p use `libx264 -crf 23 -preset fast` (lines 107–110). A naive tier table `high=20/medium=23/low=28` applied to both codecs gives "medium" 4k output that's visibly different in quality-per-bit from "medium" 1080p — x265 at a given CRF targets roughly x264 CRF+3~5 in bitrate terms (the FFmpeg wiki rule of thumb: x265 CRF 28 ≈ x264 CRF 23). Also, `preset` interacts with CRF: the same CRF at `slow` yields smaller output than at `fast`, so tier estimates tuned on 1080p/fast will under-predict 4k/slow… or rather the quality at fixed CRF shifts with preset too.

**Why it happens:**
CRF reads like an absolute quality dial. It is per-encoder, per-preset.

**How to avoid:**
Define tiers per codec explicitly — e.g. a small lookup `crf_for(codec, resolution, quality)` — and pick offsets so "medium" reproduces today's exact flags on both paths (TRANSC-02 requirement). Keep the estimate table paired to the same per-codec bitrates. Decide whether preset varies by tier; if it does, re-tune the table.

**Warning signs:**
- "Medium" looks noticeably better/worse at 4k than at 1080p on the same source
- Actual 4k sizes land far off the estimate while 1080p lands close

**Phase to address:**
Implementation phase covering TRANSC-01/TRANSC-02

---

### Pitfall 7: `quality` and picture `resolution` share the vocabulary high/medium/low — positional ambiguity

**What goes wrong:**
The 4th positional arg is `quality` ∈ {high, medium, low} — the same words already used for *picture* resolution in positional slot 3 (`omarchy transcode img.png jpg medium`). So `omarchy transcode photo.jpg jpg low` means "low resolution" today, while `omarchy transcode clip.mov mp4 1080p low` means "low quality". A user who passes a 4th arg for a picture (`... jpg medium high`) hits undefined behavior unless explicitly rejected. `usage()`, `# omarchy:args=`, and `default/agents/skills/omarchy/capture.md` (line 59 documents `<input> [format] [resolution]`) all need synchronized updates or the docs mislead.

**Why it happens:**
Vocabulary reuse across differently-shaped domains (pictures take quality-as-resolution; videos take both resolution and quality) makes the arg list position-dependent in a way users can't see.

**How to avoid:**
Validate strictly: if `type == picture` and a 4th positional is present, error clearly ("quality applies to video only") rather than silently ignoring. Update `usage()`, the `# omarchy:args=`/`# omarchy:examples=` metadata header (checked by `test/cli` metadata assertions ~line 606+), the agents skill doc, and `manual/12-screenshots-recording.md` (line 74) in the same commit.

**Warning signs:**
- `omarchy transcode pic.png png low high` silently succeeding
- Help text showing three positionals while the parser reads four

**Phase to address:**
Implementation phase covering TRANSC-02 (same commit as the arg parsing change)

---

### Pitfall 8: Estimate computation under `set -euo pipefail` turns a probe hiccup into a silent abort

**What goes wrong:**
ffprobe returns `N/A` for duration on some containers (streamed/fragmented files, some webm), and can fail outright on weird-but-playable files. Inside `est=$(ffprobe ...)` a nonzero exit under `set -e` in command-substitution assignment aborts the whole script before the menu even opens — and when launched detached (menu trigger), stderr goes nowhere the user sees. Same for `stat`, `numfmt`, `awk` math, and bash float handling (bash has no floats; `duration * bitrate` needs `awk`/`numfmt`/`bc` — `bc` is not guaranteed installed on the target system).

**Why it happens:**
The script's global `set -euo pipefail` (line 9) is right for the transcode itself but makes every new probe call a fatal branch unless guarded.

**How to avoid:**
Wrap probes: `duration=$(ffprobe ... 2>/dev/null || true)` then `[[ $duration =~ ^[0-9.]+$ ]] || duration=""` and fall back to subtexts without numbers ("Best quality" / "Smallest file") rather than dying. Do arithmetic in `awk` (posix, always present) or integer math; per AGENTS.md use `(( ))` for numeric tests and remember `(( expr ))` returns status 1 when the result is 0 — a classic `set -e` footgun in new code. Compute estimates lazily (only when the quality menu is actually shown) so `omarchy transcode in.mp4 mp4 720p low` never probes.

**Warning signs:**
- Menu never appears on one specific file but works on others
- `omarchy-transcode` exit code 1 with no output when run from a terminal — reproduces only on the odd file

**Phase to address:**
Implementation phase covering TRANSC-03

---

### Pitfall 9: Prompt count grows to four for video; Nautilus multi-select multiplies it

**What goes wrong:**
Interactive video flow becomes file → format → resolution → quality. From the Nautilus extension, `transcode.py` (lines 28–32) loops *each selected file* through the full interactive flow, so 5 files = 20 menu round-trips. Each prompt is also an Esc-exits-silently point (`format=$(...)` failing under `set -e` kills the script with no message — existing behavior, now one more chance to hit it).

**Why it happens:**
Each prompt is individually justified; the fatigue is emergent. The quality step is where the project explicitly wants to add friction *with* payoff (the estimates), so ordering matters: ask format first (quality choices differ per format), keep resolution second so the estimate table can key off it, quality last.

**How to avoid:**
- Skip the quality prompt entirely for pictures (TRANSC-06) and skip it whenever the 4th positional is supplied
- Keep `defaultIndex` on `medium` so the flow is Enter-Enter-Enter for the common case
- Consider whether gif even warrants a quality prompt vs. folding fps into the format row — requirement says gif gets fps tiers, but the subtext can carry "10 fps" so the step still earns its place
- Accept the per-file prompts in Nautilus for now; flag batch-quality-remembering as a possible follow-up, not a blocker

**Warning signs:**
- Dogfooders mashing Esc on the 4th prompt
- Nautilus "Transcode 5 items" feeling like an interrogation

**Phase to address:**
Design decision in the TRANSC-01 implementation phase; batch-prompt amortization is a candidate deferral

---

### Pitfall 10: Subtext must fit a ~300px card on one line — and becomes filter text and the return key

**What goes wrong:**
The dmenu detail renders in a single elided `Text` at `bodySmall` inside `cardWidth` ≈ `Style.space(300)` (Menu.qml lines 111, 1343–1353). Long subtexts like `"Approximately 1.2 GB at highest quality"` elide to `"Approximately 1.2 GB at hig…"`. Also: the detail participates in filter matching (lines 572–573) and is returned verbatim with the label (line 768) — so a subtext containing a literal tab would split into extra fields, and subtext wording is user-visible *and* a protocol value.

**Why it happens:**
Subtext is one string serving three roles (display, search corpus, return key).

**How to avoid:**
Keep subtexts ≤ ~30 chars (`"~120 MB · best"`, `"10 fps"`). Never let a tab into an option string. Remember the row height grows from `baseRowHeight` to `detailRowHeight` (lines 102–103, `rowHeightForDetail`) for *every* row with a subtext — three detailed rows is a taller card; that's fine, but mixing subtext/no-subtext rows in one menu produces uneven heights that look buggy.

**Warning signs:**
- Trailing `…` on subtext in the running menu
- Filter matching surprises (typing "mb" matches all rows — arguably fine)
- Returned value with more than one tab field

**Phase to address:**
Implementation phase covering TRANSC-03; verify in the running UI per `agents/skills/visual-verification.md`

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Strip subtext in transcode with `%%$'\t'*` | One line, works today | Every future subtext caller must rediscover the contract; a helper like `omarchy-menu-select --print-label` never materializes | Acceptable now — only one consumer |
| Hardcoded bitrate table in the script | No dependency, readable | Table drifts from real encoder output; needs a comment saying "calibrated against x264 fast / x265 slow" | Acceptable if estimates are presented as rough |
| `-y` on ffmpeg to dodge collisions | No hang/fail on re-transcode | Silently destroys a previous transcode the user may have wanted | Never without a deliberate decision; prefer dedupe or `-n` + warning |
| Ignore 4th positional for pictures | Less validation code | `... jpg medium ultra` silently accepted; docs drift | Never — one `if` fixes it |
| defaultIndex also applied to resolution/format menus "while we're here" | Consistent-feeling API | Changes Enter-defaults in flows users already muscle-memorized (e.g. Enter used to pick first option) | Only if a requirement calls for it |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| ffmpeg (detached launch) | Assuming a tty for the overwrite prompt | Never rely on ffmpeg interactivity; decide `-y`/`-n`/dedupe in code |
| ffprobe | Trusting `format=duration` to be numeric | Guard with `|| true` + regex check; fall back to no-number subtexts |
| `omarchy-shell shell summon` JSON payload | Hand-building JSON with new keys (defaultIndex) via string concat | Extend the existing `perl encode_json` block in `omarchy-menu-select` (lines 76–87); it already handles optional ints (`width`, `maxHeight`) — copy that pattern for `defaultIndex` |
| `wl-copy` in `copy_to_clipboard` | New code paths after it assume success | It runs before the done notification today; keep actual-size collection (stat) before or independent of clipboard so notification still fires |
| Nautilus extension | Changing `transcode.py` invocation to pass quality | It invokes with just a path *by design*; keep it that way — the interactive flow handles quality. Do not add args unless batch UX is revisited |
| `omarchy` router | Adding a flag like `--quality` before positionals | Router `exec`s the binary with remaining args; only the script's own parser matters — but a `--quality` flag inside the script's `while` loop is cleaner than relying on positional order if args grow further |
| `omarchy-notification-send` | New glyph for the done notification | Reuse existing glyphs (icon-font changes need the icon-font skill); embed size via text: `numfmt --to=iec` output |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| 4k + high tier + `-preset slow` + libx265 | Encode takes many minutes; one "Transcoding…" notification then silence; user thinks it hung | Keep `slow` only where it exists today (4k), or vary preset by tier (e.g. high=medium preset); consider an elapsed/done notification only | On laptop CPU with a multi-minute 4k source |
| ffprobe before every menu open | Menu open latency | ffprobe is ~ms on local files; only an issue on network/FUSE paths — still, compute estimates only for the quality step | Remote mounts |
| gif palette two-pass on long inputs | Two full decodes; minutes for long clips | Existing behavior; fps tiers don't change pass count — don't add a third pass | Already true today for long sources |
| `-movflags +faststart` second write | Whole-file rewrite at end; temp disk space ≈ output size | Existing; fine — but don't copy the pattern to gif | Large 4k outputs on nearly-full disks |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Unquoted new `quality`/path vars in ffmpeg args | Filename with spaces splits args | Follow existing `"$var"` quoting everywhere; the script already does this correctly |
| Filenames containing tabs passed as menu options | Tab splits glyph/label/subtext fields; wrong row selected/returned | File listing path uses `cut -f2-` (tabs survive in filenames); low risk since filenames-with-tabs are rare — note it, don't engineer for it |
| `output_path` derived from attacker-ish stem | stem is only `basename %.*` — `..` or `/` cannot survive `dirname/basename` | Existing code already safe; keep new suffix appended after sanitization |
| Estimate math via `eval` or unvalidated ffprobe output | ffprobe output is attacker-controlled (crafted file) | Treat probe output as data: regex-validate before arithmetic; never `eval` |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Fake-precision estimate ("≈43.7 MB") | Trust, then betrayal when actual is 180 MB | `~40 MB` or a range; consider "usually X–Y MB" |
| Estimate says smaller, output comes out larger than input | User blames the tool | Detect estimate > source size and say "may be larger than original"; the done notification can also show the delta ("48 MB (was 32 MB)") |
| Enter on quality picks "high" (index 0) | Defaults change silently vs the project's stated `medium`-default intent | `defaultIndex` = medium's index (TRANSC-05) — but ONLY on the new quality menu; don't retro-apply to resolution/format |
| Quality prompt for gif shows MB estimates | Numbers are fiction for gif | Subtext = fps ("15 fps", "10 fps", "6 fps"), not size |
| Done notification omits the filename or size | User can't tell which transcode finished (Nautilus batch) | Include basename + actual size: `clip-1080p.mp4 · 48 MB` |
| Uneven row heights when only some rows have subtext | Card looks broken | Give all three quality rows subtexts, or none |
| Upscaled 4k from 1080p source marketed as "4k high" | Huge file, zero gain, feels like a scam | Optionally note in subtext when source < target height — or defer; at minimum the estimate reflects the big number |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Quality arg:** Often missing validation that a 4th positional on a *picture* errors instead of being ignored — verify `omarchy transcode img.png jpg medium high` exits nonzero with a message
- [ ] **Subtext stripping:** Often missing `${var%%$'\t'*}` on the menu result — verify the interactive path (not just the positional path) reaches the `case` match
- [ ] **defaultIndex clamping:** Often missing out-of-range/negative handling — verify `-- --default-index 99` doesn't wedge the menu (QML clamp in `rebuildDmenuDisplay` covers this if set pre-rebuild)
- [ ] **Filter interaction:** Often missing re-check that typing in the quality menu still works — `setFilter` resets `selectedIndex` to 0, so defaultIndex is initial-only; that's acceptable but confirm no crash when filtered count < defaultIndex
- [ ] **Collision path:** Often missing the second-run case — verify transcode twice at same settings doesn't hang (terminal) or silently die (keybind)
- [ ] **N/A duration:** Often missing fallback subtext when ffprobe yields `N/A` — verify on a truncated/odd file that the menu still opens with plain labels
- [ ] **medium byte-compat:** TRANSC-02 says medium reproduces current flags *exactly* — verify by diffing the ffmpeg command line (`set -x` or echo) for `mp4 1080p medium` vs today's flags
- [ ] **Docs/metadata sync:** Often missing `usage()`, `# omarchy:args=`, `capture.md` skill doc, and `manual/12-screenshots-recording.md` updates in the same commit — `test/cli` checks metadata shape (~line 606)
- [ ] **Caller sweep:** All 16 `omarchy-menu-select` callers must still work — verify at least the stdin-fed ones (timezone, keybindings, plugin) after the `--` arg parsing change
- [ ] **Visual check:** Subtext elision at 300px and the taller detailRowHeight card need running-UI verification per `agents/skills/visual-verification.md`, not just tests

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Subtext leaks into `case` | LOW | Add `%%$'\t'*` strip; no user-visible harm beyond failed run |
| Bad estimate shipped | LOW | Adjust the table constants; estimates are advisory — no data corrupted |
| Overwrite policy wrong (chose `-y`, clobbered a file) | MEDIUM | Re-transcode from source; switch to dedupe; the clobbered file is unrecoverable unless source re-encoded — that's why policy must be deliberate upfront |
| defaultIndex breaks a caller | MEDIUM | Revert is clean if implemented as a `--` arg (additive, ignored-safe); positional would require coordinated revert |
| 4k/high encode too slow | LOW | User Ctrl-C's the terminal; nothing written partially? (partial mp4 without faststart moov is unplayable but harmless — it's deleted manually) |
| Silent abort on odd file | LOW | Guard probes post-hoc; user can still use positional args to bypass menus |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls. (v1.1 phases are not yet written into ROADMAP.md; mapping is by requirement ID — fold each into the phase that implements it.)

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. Subtext in return value | TRANSC-01/03 implementation | Interactive pick of each tier reaches correct ffmpeg flags |
| 2. defaultIndex arg design | TRANSC-05 implementation | All 16 callers unbroken; stdin-fed menus intact; Enter lands on medium |
| 3. Fake-precision estimates | TRANSC-03 implementation | Estimates within ~2–3× on 3 varied real clips; `~` prefix present |
| 4. Collision/overwrite | TRANSC-01 implementation | Second identical transcode: defined behavior in both tty and detached paths |
| 5. Audio floor in estimates | TRANSC-03 implementation | Short-clip estimate within ~25% of actual |
| 6. x265/x264 CRF offset | TRANSC-01/02 implementation | `medium` diffs clean vs current flags on both codec paths |
| 7. Positional vocabulary collision | TRANSC-02 implementation | Picture + 4th arg errors; help/metadata/docs updated |
| 8. Probe failure under set -e | TRANSC-03 implementation | Crafted/N-A-duration file still opens the menu |
| 9. Prompt fatigue | TRANSC-01 design | Video interactive flow = ≤4 prompts, Enter×3 gives medium defaults; pictures unchanged |
| 10. Subtext width/protocol | TRANSC-03 implementation | No elision at 300px; no tabs in subtext; visual verification done |
| Deferred: batch prompt memory in Nautilus | Post-v1.1 candidate | Revisit if dogfooding complaints |
| Deferred: HDR sources → washed-out SDR | Out of scope for v1.1 | Pre-existing issue; note if "high" tier makes it more visible |

## Sources

- `bin/omarchy-transcode` (full read — arg parsing, encoders, output naming, notification flow)
- `bin/omarchy-menu-select` (full read — `--` arg boundary, stdin option source, perl JSON payload)
- `shell/plugins/menu/Menu.qml` (full read — `openDmenu`, `rebuildDmenuDisplay`, subtext return at line 768, elided detail text, ~300px `cardWidth`, `setFilter` resetting `selectedIndex`)
- `default/nautilus-python/extensions/transcode.py` (path-only invocation, per-file loop)
- `default/omarchy/omarchy-menu.jsonc` line 69 (detached menu trigger), `default/hypr/bindings/utilities.lua` line 87 (keybinding)
- `bin/omarchy` dispatch (lines 949–1048 — router execs remaining args verbatim; `omarchy-transcode-ascii` longest-prefix routing note)
- `test/cli` metadata assertions (~line 606), `test/shell.d/menu-plugin-test.sh` (menu-select is stubbed — arg-shape changes won't be caught there)
- `.planning/PROJECT.md` v1.1 requirements TRANSC-01..06
- FFmpeg wiki x264/x265 CRF equivalence guidance (x265 CRF ≈ x264 CRF + several points for comparable quality); ffmpeg overwrite-prompt stdin behavior; `set -e` + `(( ))` status-1-on-zero footgun per bash docs
- Omarchy `AGENTS.md` style rules (`[[ ]]`, `(( ))`, `#!/bin/bash`, atomic commits, visual verification requirement)

---
*Pitfalls research for: quality tiers + size estimation in omarchy-transcode*
*Researched: 2026-09-15*
