# Stack Research

**Domain:** CLI media transcoding — target output size (`--target <size>`, SIZE-10) for `bin/omarchy-transcode` via ffmpeg two-pass encoding, plus a "Custom size…" free-text row in the interactive quality menu (Menu.qml input mode)
**Researched:** 2026-09-16
**Confidence:** HIGH throughout — every ffmpeg flag below was run against the installed n9.0.1 build (two-pass verified end-to-end for both libx264 and libx265; gif bitrate-independence verified empirically), and the menu-input path is already shipped code, not proposed API.

## Recommended Stack — no new dependencies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| ffmpeg two-pass (`-pass`, `-passlogfile`, `-b:v`, `-f null`) | n9.0.1 installed; flags stable for >10 yrs | Fit mp4 output to a named byte target | Two-pass is the designed mechanism for *size* targets: pass 1 writes per-frame stats, pass 2 spends exactly the `-b:v` budget. Verified: 500k video + 192k audio over 3.0 s → 241,236 B (x264) / 231,229 B (x265) vs ~260 KB nominal — lands within a few % under target |
| ffprobe (`video_duration`, `video_audio_kbps`) | same package | Duration + audio presence for bitrate math | Already shipped in v1.1 — `video_duration` (bin/omarchy-transcode:162) and `video_audio_kbps` (:172) return exactly the two inputs the bitrate formula needs. Zero new probing code |
| `numfmt --from=iec` (coreutils) + bash regex | system | Parse `25M`/`1.5G` → bytes | `--from=iec` uses the MiB convention the completion notification already labels "MB" (MiB arithmetic, PROJECT.md decision). **But it is stricter than free text deserves:** accepts `25M`/`1.5G`/`500K`, rejects `25MB`, `25m`, `25MiB`; bare `25` parses as 25 *bytes*. Pre-validate with a regex, normalize (strip optional `B`, uppercase unit, default bare number to `M`), then feed numfmt — or do the whole parse in awk. Either way the regex gate must come first for friendly errors |
| awk | system | Bitrate arithmetic (`bytes×8/dur−audio`) | Same float-math convention as v1.1's `estimate_label` (bin/omarchy-transcode:229); bash can't divide floats |
| `bin/omarchy-menu-input` | already shipped | Free-text "Custom size…" prompt | **Exists today** — emits `mode:"input"` + `selectionFile`/`doneFile` handshake, supports `--width`. `omarchy-menu-select` needs NO changes |

## ffmpeg Two-Pass Mechanics — verified on n9.0.1

Canonical shape (mirroring `transcode_video`'s existing codec/scale flags):

```bash
passdir=$(mktemp -d)
# pass 1 — stats only: no audio, null muxer, no faststart
ffmpeg -i "$input" -vf "$scale" -c:v libx264 -preset fast \
  -b:v "${kbps}k" -pass 1 -passlogfile "$passdir/2pass" \
  -an -f null /dev/null
# pass 2 — full encode: audio + faststart move here
ffmpeg -i "$input" -vf "$scale" -c:v libx264 -preset fast \
  -b:v "${kbps}k" -pass 2 -passlogfile "$passdir/2pass" \
  -c:a aac -b:a 192k -movflags +faststart "$output"
rm -rf "$passdir"
```

- **`-passlogfile` naming:** on n9.0.1 both encoders write `<prefix>-0.log` plus `<prefix>-0.log.mbtree` (x264) / `<prefix>-0.log.cutree` (x265) — identical suffix convention, so no per-codec path handling. Put the prefix inside a `mktemp -d` and delete the directory whole; never enumerate the suffixes.
- **`-an` on pass 1:** audio is skipped for stats (it doesn't affect rate control) and encoded fresh in pass 2. Saves the AAC encode on the throwaway pass and keeps the null muxer trivially satisfiable.
- **`-f null /dev/null`:** correct null-muxer spelling on Linux (this codebase is Linux-only).
- **`-movflags +faststart` on pass 2 only:** it's a muxer-level flag — meaningless on the null muxer, and it does a second file rewrite that belongs on the real output.
- **Presets:** libx264's `-fastfirstpass` already defaults to `true` (verified via `ffmpeg -h encoder=libx264`), so pass 1 runs reduced-effort settings automatically — do NOT wire a different `-preset` per pass. libx265 honors `-pass`/`-passlogfile` through the same AVOptions (verified; also exposes `-x265-stats` as an alternative spelling — don't use it, `-passlogfile` covers both codecs uniformly).
- **Bitrate math:** `total_kbps = target_bytes × 8 ÷ duration_s ÷ 1000`; `video_kbps = total_kbps − audio_kbps − overhead`. Reserve ~2–3% for mp4 container + faststart rewrite (x264 two-pass already lands a few % *under* nominal, so a small margin plus its natural undershoot ≈ on-target). `video_audio_kbps` already returns the right 192-or-0 value.
- **Floors / step-down:** below some per-resolution kbps the picture is mush — that's a quality floor, an encode can't fix it. The existing resolution ladder has exactly three rungs (4k→1080p→720p, `transcode_video`'s scale case at bin/omarchy-transcode:112); stepping *below* 720p needs new `scale=-2:480`/`-2:360` entries — a design decision for the plan, not a stack gap. Rough grounding for floors: 2160p ~2 Mbps, 1080p ~800 kbps, 720p ~400 kbps minimum-watchable for typical content. Below the lowest floor: refuse honestly (milestone language), don't encode garbage.
- **Failure behavior is free:** `set -euo pipefail` + ffmpeg's nonzero exit on bad input means a failed pass 1 aborts before pass 2 runs — matches the existing single-pass path.
- **Codec selection stays resolution-gated:** keep x265 for 4k, x264 for 1080p/720p exactly as `transcode_video` does — two-pass works identically on both.

## GIF Target — confirmed meaningless (refuse, as specced)

**Verified:** same 1 s gif produced byte-identical 263,031 B at `-b:v 100k` and `-b:v 5000k` — the gif encoder (palettegen → paletteuse) has no rate control at all. GIF size is driven by fps, geometry, `max_colors`, and dither — none of which accept a byte budget. `-b:v` is silently ignored. `--target` on gif must error, matching the milestone's "gif refuses `--target`" requirement. (A loop-until-fits sample-encode is a different feature — that's deferred SIZE-12 territory, not this milestone.)

## Menu Input Mode — what's already there

`payload.mode === "input"` is supported **today**; `omarchy-menu-select` does not need to change because a dedicated sibling already emits it.

| Question | Answer (file:line) |
|----------|---------------------|
| Does the payload support `mode:"input"` today? | Yes — `Menu.qml:27` routes `select`/`input` to `openDmenu`; `:866` sets `mode`. `bin/omarchy-menu-input` (whole file) builds the payload and handshake |
| Does `omarchy-menu-select` need changes? | **No.** It hardcodes `mode:"select"` (bin/omarchy-menu-select:89) and that's correct — input prompts go through `omarchy-menu-input`. Don't graft a `--input` flag onto menu-select |
| Validation in input mode? | **None.** Enter/Return submits `root.filterText` verbatim (Menu.qml:765-767, :1158-1160). All validation is the bash caller's job |
| Placeholder? | No separate field — the prompt doubles as placeholder: header shows `filterText` at full opacity or `prompt + "…"` dimmed at 0.58 (Menu.qml:1210-1212). No prefill exists (`filterText` always starts `""`, :877) |
| Options in input mode? | Ignored entirely — `rebuildDmenuDisplay` early-returns for input mode (:558-561); `omarchy-menu-input` doesn't send an `options` field at all |
| Return contract | `omarchy-menu-input` prints the typed text + `\n`, exit 0 on submit; exit 1 on cancel |

**Input-mode quirks the caller must own:**

- **Empty submit ≠ cancel.** Enter on an empty field writes `\n` to `selectionFile` (1 byte, `-s` true) → prints an empty line, **exit 0**. Cancel is Esc-with-empty-text → `finishRequest(null)` → exit 1. So `omarchy-menu-input` returning empty-with-0 means "user submitted nothing" — treat as invalid/reprompt, not as cancel.
- **Esc is two-stage:** first Esc clears non-empty text (Menu.qml:1137), second Esc cancels. Expected, but means a user can't Esc-cancel with text present without clearing first.
- **Right-arrow submits too** (Menu.qml:1158 folds `Key_Right` into the Enter branch). Harmless but undocumented-looking.
- **Editing keys:** printable chars incl. space appended via the `event.text` path (:1165-1167); Backspace / Ctrl+Backspace / Ctrl+U handled by `Util.editsFilter`/`editedFilter` (shell/Commons/Util.qml:111-126). No regex, no maxLength, no masking — a size field gets whatever the user types.
- **`--width` works** (`dmenuWidth` applies to the collapsed card, Menu.qml:112); `--default-index`/`--maxheight` are meaningless (no rows) and `omarchy-menu-input` doesn't accept them anyway.
- **Suggested prompt shape:** `omarchy-menu-input "Target size (e.g. 25M)"` — the example-in-prompt pattern is the only "placeholder" affordance available.

## Integration Points

- **"Custom size…" row:** `select_quality` (bin/omarchy-transcode:247) builds rows as `\t<label>\t<subtext>` and re-validates the stripped label against `high|medium|low` (:279-285). A 4th row fits the wire format naturally; the return is the *display label*, so the sentinel check is `[[ $selection == "Custom size…" ]]` (or normalize — design call). On match, hand off to `omarchy-menu-input` + the size parser. Note the existing re-validation will reject "Custom size…" as an invalid quality unless the case is extended — that's the intended chokepoint.
- **`--target` flag:** the arg loop (:305-331) has a clean `--path` precedent for valued options. Parse-and-validate early — format/resolution validation is already hoisted ahead of menus and the start notification (v1.1 close decision); `--target` + gif/picture refusal belongs in the same early block so a bad combination dies before the "Transcoding video…" toast.
- **Bitrate derivation:** `video_duration` (:162) + `video_audio_kbps` (:172) are drop-in. On `video_duration` failure there's no duration → no bitrate → refuse honestly (same honesty convention as `estimate_label`'s qualitative fallback).
- **`output_path`:** takes quality as its 4th arg for the filename suffix (:49-72, non-"medium" values append). A target run needs *some* 4th-field token or a naming decision — passing the normalized target (`25M`) produces `stem-1080p-25M.mp4`, which is self-documenting. Design call, cheap either way.
- **Two-pass + `select_quality` interaction:** `--target` and quality are mutually exclusive inputs (one picks bitrate, the other CRF). CLI precedence rule needed: `--target` + positional quality → error, or `--target` wins — decide in plan, validate early.
- **Tests:** `test/shell.d/transcode-quality-test.sh` stubs ffmpeg recording `%q`-joined argv and synthesizes output under `FAKE_OUT_BYTES` — a two-pass path just records two invocations (stub sees `-pass 1` then `-pass 2`); extend the same stub, don't build a new harness. `menu-select-test.sh` covers the menu contract if the row shape changes.

## Installation

```bash
# Nothing to install. ffmpeg n9.0.1 (with libx264+libx265), numfmt, awk,
# mktemp are all present; omarchy-menu-input is already shipped.
```

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Changes to `omarchy-menu-select` or `Menu.qml` | `mode:"input"` and its dedicated `omarchy-menu-input` wrapper already exist and are documented (`docs/menu.md` "Select and input modes") | Call `omarchy-menu-input` |
| `-fs` (file-size limit) | It truncates the encode mid-file when the cap is hit — an abort valve, not a targeting mechanism; produces short/broken outputs | Two-pass `-b:v` |
| Single-pass `-b:v` (ABR) | Legal and would roughly hit the size, but measurably worse quality-per-bit than two-pass at the same bitrate — the entire point of the feature | Two passes |
| `-maxrate` / `-bufsize` / `-minrate` | Streaming/decoder-buffer caps; they constrain bitrate *shape*, not total size. Adds failure surface for zero targeting benefit | Plain `-b:v` |
| `-x265-params stats=…` / `-x265-stats` | `-pass`/`-passlogfile` already drive x265's stat files correctly on n9.0.1 (verified) — hand-wiring duplicates it per-codec | `-passlogfile` uniformly |
| Per-pass `-preset` switching | libx264 `-fastfirstpass=true` already cheapens pass 1; manual preset divergence adds a flag surface for marginal speed | Same preset both passes |
| QML-side validation/placeholder/maxLength | Menu.qml has none and the feature doesn't justify growing any — a size string is one regex in bash | Validate in the caller |
| gif `--target` support of any kind | Verified: `-b:v` is ignored by the gif encoder (byte-identical outputs at 100k vs 5000k) | Refuse with an error |
| Encode-retry loops to converge on size | Two-pass lands within a few % — chasing the last 2% costs full re-encodes | Accept the tolerance |
| `bc`, `mediainfo`, `jq` | awk + ffprobe + perl-JSON::PP are the repo's existing conventions | Reuse them |
| `omarchy-cmd-present` guards on ffmpeg/numfmt | De-facto runtime invariants per v1.1 research | Invoke directly |

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `-pass`/`-passlogfile`/`-b:v`/`-an`/`-f null` | ffmpeg n9.0.1 (verified), effectively any ffmpeg with libx264/libx265 | These flags predate every supported ffmpeg by years — no version guard needed. The passlogfile *suffix* convention (`-0.log` for both encoders) was verified on n9.0.1; if it ever diverged, the `mktemp -d` + whole-dir cleanup makes it irrelevant |
| `numfmt --from=iec` | coreutils on Arch | Suffix behavior verified above; strictness handled by pre-validation |
| `omarchy-menu-input` | shipped in-repo | Same tempfile handshake as menu-select; no new contract |

## Sources

- **Empirical (this environment):** ffmpeg n9.0.1 two-pass runs for libx264 (`-0.log` + `-0.log.mbtree`, 241,236 B out) and libx265 (`-0.log` + `-0.log.cutree`, 231,229 B out) against a generated 3 s test clip; gif `-b:v` invariance (263,031 B at 100k vs 5000k); `numfmt --from=iec` accept/reject table; `ffmpeg -h encoder=libx264` showing `-fastfirstpass` default true and `-passlogfile`.
- **Repo:** `bin/omarchy-transcode` (helpers at :162/:172/:229, `select_quality` at :247, arg loop at :305), `bin/omarchy-menu-input` (complete input-mode wrapper), `bin/omarchy-menu-select` (select-only payload, :89), `shell/plugins/menu/Menu.qml` (input routing :27, openDmenu :864-885, input submit :765-767/:1160, prompt-as-placeholder :1210-1212), `shell/Commons/Util.qml:111-126` (edit keys), `docs/menu.md` "Select and input modes", `test/shell.d/transcode-quality-test.sh` (argv-stub pattern), v1.1 `.planning/research/STACK.md` (which pre-identified two-pass as "documented future work" with the correct `-an` + null-muxer shape).

---
*Stack research for: omarchy-transcode `--target <size>` two-pass encoding + Custom size menu input*
*Researched: 2026-09-16*
