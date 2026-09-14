# Architecture Research

**Domain:** Interactive media transcoding — bash CLI + Quickshell/QML dmenu (Omarchy fork)
**Researched:** 2026-09-15
**Confidence:** HIGH — all touch points read end-to-end; upstream PR #6698 diff reviewed in full

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  ENTRY POINTS (all invoke bin/omarchy-transcode, no shared state)   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │ omarchy-menu.jsonc│  │ Hyprland binding │  │ Nautilus extension│  │
│  │ trigger.transcode │  │ (utilities.lua)  │  │ transcode.py      │  │
│  │  (line 69)        │  │                  │  │ (prompts run)     │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬──────────┘  │
└───────────┼─────────────────────┼─────────────────────┼─────────────┘
            └─────────────────────┴─────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  bin/omarchy-transcode  — arg parse → prompts → ffmpeg / magick     │
│    media_type()  output_path()  transcode_picture()                 │
│    transcode_video()  copy_to_clipboard()  main()                   │
└───────────┬─────────────────────────────────────────────────────────┘
            │  prompt/options/selectionFile/doneFile JSON payload
            ↓
┌─────────────────────────────────────────────────────────────────────┐
│  bin/omarchy-menu-select → omarchy-shell → `qs ipc call`            │
│  → shell/plugins/menu/Menu.qml  openDmenu(payload)                  │
│  writes "label<TAB>subtext" to selectionFile, touches doneFile      │
└─────────────────────────────────────────────────────────────────────┘
            ↓
     ffprobe (duration) → bitrate table → row subtext (estimates)
     ffmpeg / magick (actual transcode) → stat/numfmt (actual size)
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `bin/omarchy-transcode` | Arg parsing, interactive prompts, encoder flag selection, output naming, notifications | Single bash file, `main()` dispatch, `case` tables for resolution→scale/format→flags |
| `bin/omarchy-menu-select` | Build select-mode JSON payload, block on tempfile handshake, return selection | Perl `JSON::PP` payload builder (lines 76–87), poll loop on `doneFile` (91–93) |
| `shell/plugins/menu/Menu.qml` | Render dmenu rows, track cursor (`selectedIndex`), write result | `openDmenu` (861–881), `rebuildDmenuDisplay` (553–603), `finishRequest` (117–135) |
| `shell/plugins/menu/MenuModel.js` | Pure-logic helpers, unit-testable from node via `run_node_test` | Requirable module (see `menu-test.sh:9`) |
| `default/nautilus-python/extensions/transcode.py` | Context-menu entry; invokes bare `omarchy-transcode <path>` so all prompts run | `_launch_transcode` (lines 19–34); **no change needed** for this feature |

## Where Each Change Lands

### 1. `bin/omarchy-transcode` (207 lines today)

| Location | Change |
|----------|--------|
| Metadata header, lines 6–7 | `# omarchy:args=` gains `[quality]`; add an example like `omarchy transcode ~/Videos/demo.mov mp4 1080p low`. `test/cli` validates command metadata (see `agents/skills/command-metadata.md`) |
| `usage()` lines 11–30 | Usage line gains `[quality]`; add `Qualities: Videos: high, medium, low` block |
| `output_path()` lines 46–57 | Add 4th param `quality`; emit `stem-resolution-quality.format` only when quality is set **and** ≠ `medium` (TRANSC-06 — default keeps today's `stem-1080p.mp4` name byte-identical) |
| `transcode_video()` lines 91–121 | Add 5th param `quality`; extend the `case "$format"` arms. `medium` must reproduce current flags exactly: x264 `-crf 23 -preset fast`, x265 (4k) `-crf 24 -preset slow`, gif `fps=10` (TRANSC-02). Suggested tiers: x264 high/low = crf 19/28; x265 21/29; gif fps 15/5. Invalid quality → error like lines 100–102 |
| New `video_duration()` | `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input"` → float seconds |
| New `video_bitrate_kbps()` | Nested `case` on `format`→`resolution`→`quality` returning an assumed kbps (matches existing case-table style; `declare -A` would also work but case fits file style) |
| New `estimated_size()` | `bytes = duration × kbps × 1000 / 8`, then `numfmt --to=iec --suffix=B` (coreutils — already a platform invariant) → `~45MB` |
| `main()` line 132 | `local ... quality=""` added |
| `main()` line 165 | `quality="${positional[3]:-}"` — 4th positional, optional |
| After resolution block, lines 185–191 | New video-only block: `if [[ $type == "video" && -z $quality ]]` → build rows `"$'\t'high\t~120MB"` … → `omarchy-menu-select "Select quality" … -- --default-index 1` → strip subtext (see § Subtext-return parsing). Must come **after** format+resolution prompts since estimates key on both |
| Lines 193–199 | `output_path` gains `$quality` arg; completion notification gains actual size: `$(numfmt --to=iec --suffix=B "$(stat -c %s "$output")")` appended to the "Saved and copied…" message |

`transcode_picture()` (59–89) is untouched — pictures never see quality (TRANSC-06). If a caller passes a 4th positional for a picture, recommended behavior: ignore it (or reject with a usage error — pick one and test it).

### 2. `bin/omarchy-menu-select` (99 lines today)

- Line 27 area: add `menu_defaultindex=""`.
- Post-`--` flag loop, lines 32–53: add a `--default-index` arm mirroring `--width` (value-required guard, assign `menu_defaultindex="$1"`). Kebab-case matches `--maxheight`.
- Perl payload, lines 76–87: add `$payload->{defaultIndex} = int($ARGV[6]) if length($ARGV[6] // "");` and append `"$menu_defaultindex"` to the argv list — identical pattern to `width`/`maxHeight` (omitted field when flag absent → full back-compat for every existing caller).
- Header doc comment lines 9–13 and both usage strings (lines 18, 67) mention the new flag; `# omarchy:args=` line 6 unchanged (flags already live behind `[-- menu args...]`).
- Also update `docs/menu.md` "Select and input modes" (lines 156–167) to document `defaultIndex`.

Alternative considered: a label-based `--default medium` resolved to an index in bash before building the payload. More caller-friendly but more code; index is what the spec names (`defaultIndex`) and the transcode script knows its row order. Label-based can be added later without breaking anything.

### 3. `shell/plugins/menu/Menu.qml` (1480 lines today)

All changes inside `openDmenu` (861–881) plus one property:

- Near `dmenuMaxHeight` (line 62): `property int dmenuDefaultIndex: 0`.
- In `openDmenu` after line 870: `dmenuDefaultIndex = Math.max(0, Number(payload.defaultIndex || 0))` — same coercion pattern as `dmenuWidth`.
- Line 874 `selectedIndex = 0` → `selectedIndex = dmenuDefaultIndex`. **Why this is safe:** `rebuildDmenuDisplay` (called via `rebuildDisplay` at line 878) already clamps `selectedIndex` into `[0, count-1]` at lines 596–598, so an out-of-range payload can't wedge the cursor. At open, `filterText` is `""` so `displayModel` indices align 1:1 with `dmenuOptions` indices (the skip-at-572 only happens under a query).
- `cursorActive` is already `true` in select mode (line 875), so Enter hits `activateIndex(root.selectedIndex)` at line 1157 — the default row is the Enter-default with zero further work.
- `Qt.callLater(revealCursor)` at lines 600–602 scrolls the default row into view.
- **Testability recommendation:** put the `Number(payload.defaultIndex || 0)` → clamped-index resolution in `MenuModel.js` (e.g. `dmenuDefaultIndex(payload, optionCount)`) so `menu-test.sh`'s `run_node_test` harness can cover it; `Menu.qml` then calls `MenuModel.dmenuDefaultIndex(...)`. This matches the established split (all menu logic lives in the requirable JS, QML stays thin).
- Input mode (`mode === "input"`) ignores the field naturally — `cursorActive` stays false.

**Interaction caveat:** `setFilter` (line 722) resets `selectedIndex = 0` on the first keystroke. That's correct — `defaultIndex` is an initial position, not a persistent anchor — but worth a comment so nobody "fixes" it later.

## Data Flow

### Estimate flow (new)

```
$input ──ffprobe──▶ duration_s ──┐
                                 ├─▶ est_bytes = s × kbps × 1000 / 8
format+resolution+quality ──case table──▶ kbps ──┘        │
                                 numfmt --to=iec ◀────────┘
                                      ↓
                     row = "\t" + label + "\t" + "~" + size
                                      ↓
              omarchy-menu-select … -- --default-index 1
                                      ↓
                        selection = "low\t~9MB"
                                      ↓
                    quality=${selection%%$'\t'*}
```

### Key Data Flows

1. **Selection return contract:** `activateIndex` (Menu.qml:768) writes `label + "\t" + detail` when a subtext exists. The transcode script must take field 1: `quality=${selection%%$'\t'*}`. Precedent: `bin/omarchy-menu-plugin:36` uses `cut -f2` for exactly this reason.
2. **Row construction contract:** in `rebuildDmenuDisplay` (Menu.qml:568–571), when an option contains a tab the **first** field is consumed as the glyph/icon. So a no-glyph `label\tsubtext` row must be sent as `"\tlabel\tsubtext"` (leading empty glyph field), or use a real glyph per row. Sending bare `"high\t~120MB"` would render "high" as an icon and "~120MB" as the label — silent breakage.
3. **Estimate timing:** `ffprobe` runs **only** inside the `type == "video" && -z $quality` prompt branch — a non-interactive call (Nautilus, scripts) never pays for it.
4. **Actual size:** `stat -c %s` + `numfmt` on the finished output, appended to the existing completion notification at `omarchy-transcode:199`.

## Scaling / Scope Considerations

| Concern | Adjustment |
|---------|------------|
| Long inputs | `ffprobe` reads container headers only — O(1), no decode; fine on any size |
| Estimate accuracy | Table values are nominal bitrates for typical screen-share content; prefix `~` and keep one sig-fig-ish rounding. Do not sample-encode — too slow for a menu |
| gif estimates | Far less predictable than mp4; either ship a conservative MB/s-per-megapixel table or omit subtext for gif rows (labels stay uniform) |
| Folder batch (PR #6698) | If merged, quality would prompt once per batch or thread through as arg — see below |

## Anti-Patterns

### Anti-Pattern 1: Bare `label\tsubtext` option rows

**What people do:** `omarchy-menu-select "Quality" "high\t~120MB" …`
**Why it's wrong:** the first tab-field is eaten as the icon (Menu.qml:569), so the subtext becomes the label and the estimate is lost.
**Do this instead:** `"\thigh\t~120MB"` (empty glyph) or a real leading glyph.

### Anti-Pattern 2: Reusing `resolution`-style prompt ordering

**What people do:** prompt quality before resolution.
**Why it's wrong:** the estimate subtext is keyed on format × resolution × quality — quality must come last, as the 4th prompt.
**Do this instead:** keep file → format → resolution → quality.

### Anti-Pattern 3: Encoding "default" inside the option string

**What people do:** a marker like `"medium*"` or a 4th tab-field the QML special-cases.
**Why it's wrong:** whatever rides in the row comes back in the selection string; the caller would have to strip it. The payload field keeps presentation out of the return contract.
**Do this instead:** `--default-index N` → `defaultIndex` payload field → `dmenuDefaultIndex` property.

### Anti-Pattern 4: Changing medium's flags or the default filename

**What people do:** "improve" crf values or always suffix `-medium`.
**Why it's wrong:** TRANSC-02/06 require omitted/medium to be byte-identical in flags and filename; anything else breaks every existing caller and upstream-diff reviewability.
**Do this instead:** medium = today's literals; suffix only for high/low.

## Upstream Interaction: PR #6698 (folder transcoding)

PR #6698 (`omacom/omarchy`, open, +326/−33, touches `bin/omarchy-transcode`, `transcode.py`, `migrations/1786437940.sh`, **new `test/shell.d/transcode-test.sh`**) conflicts with this feature at four sites:

1. **`main()` tail.** The PR replaces lines 193–204 (`output=$(output_path …)` + direct transcode calls) with `output=$(transcode_file …)`. Our change edits the same hunk (quality arg, suffix, notification size). Whichever lands second rebases this region — unavoidable textual conflict.
2. **`output_path` signature.** The PR calls it inside new `transcode_file` with 3 args; we add a 4th (`quality`). Signature change + their new call site = conflict in `transcode_file` and its `transcode_directory` caller.
3. **Insertion point.** The PR inserts `media_type_for_format`/`transcode_file`/`transcode_directory` between `transcode_video` and `copy_to_clipboard` (~line 132); our new `video_duration`/`video_bitrate_kbps`/`estimated_size` want the same neighborhood. Keep new functions adjacent to `transcode_video` or below `copy_to_clipboard` to shrink the conflict window.
4. **Test file collision.** The PR creates `test/shell.d/transcode-test.sh`. **Recommendation: name ours `transcode-quality-test.sh`** — avoids an add/add conflict entirely; if the PR merges first, suites coexist.
5. **Semantics.** The PR's Nautilus `_batch_command` prompts once for format+resolution then runs `omarchy-transcode <path> "$format" "$resolution"` per file — with our feature, each video file would re-prompt for quality. Follow-up needed on whichever side merges second (batch should capture quality once and pass the 4th positional). Our optional-4th-arg design keeps their call sites working unchanged meanwhile.

## Build Order

1. **Menu `defaultIndex` plumbing** — `omarchy-menu-select` flag + `Menu.qml`/`MenuModel.js` change. Self-contained; every existing caller unaffected (field absent ⇒ index 0). Node-testable via `menu-test.sh` + a payload-capture `omarchy-shell` stub.
2. **`omarchy-transcode` non-interactive quality** — 4th positional, `transcode_video` flag tables, `output_path` suffix. Testable with zero menu involvement.
3. **Interactive quality prompt + estimates** — `ffprobe` helper, bitrate table, row building, `--default-index 1`, subtext-strip parsing.
4. **Completion-notification size** — `stat`/`numfmt` one-liner in `main()`.
5. **Docs/metadata** — usage text, `# omarchy:*` header, `docs/menu.md`.

Steps 1–2 are independent and could land as separate atomic commits (Omarchy convention: atomic single-concern commits); 3–4 belong to the transcode commit series.

## Test Coverage (per `test/shell.d` conventions)

New `test/shell.d/transcode-quality-test.sh`, stub pattern per `monitor-scaling-test.sh`/`menu-plugin-test.sh`/PR-#6698's test:

- Stub `file` (mime by extension), `ffmpeg`/`magick` (record args, `touch "${!#}"`), `ffprobe` (echo fixed duration), `wl-copy`, `omarchy-notification-send` (record args), `omarchy-menu-select` (record `"$@"`, answer `$FAKE_PICK`), `omarchy-shell` (capture payload JSON; satisfy handshake by writing pick→`selectionFile`, touching `doneFile` — paths parseable from the payload with perl/python3 since JSON::PP is already a script dep).
- Assert: `medium` and omitted quality → exact current ffmpeg args (`-crf 23` / `-crf 24` / `fps=10`) and unsuffixed filename; `high`/`low` → mapped flags + `-high`/`-low` filename; gif → fps tiers; picture input → menu-select never invoked with a quality prompt; stub returning `"low\t~9MB"` → still produces `*-low.mp4` (subtext stripped); captured menu rows contain `\t`-joined estimates; `--default-index` surfaces as `defaultIndex` in the captured payload; notification text contains the stubbed size.
- Menu side: extend `menu-test.sh`'s `run_node_test` block against the new `MenuModel.js` helper (default/clamp/out-of-range/absent-field cases); `Menu.qml` itself is covered by the file-read assertion pattern already used at `menu-test.sh:10`.
- QML visual check per `agents/skills/visual-verification.md`: quality menu opens with cursor on `medium`.

## Integration Points

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `omarchy-menu-select` ↔ `Menu.qml` | JSON payload via `omarchy-shell shell summon` → `open(payloadJson)`; tempfile handshake | `omarchy-shell` (line 51–59) passes payload opaquely to `qs ipc` — no shell-side schema; new field is end-to-end additive |
| `omarchy-transcode` ↔ `omarchy-menu-select` | argv options `[\t]glyph\tlabel\tsubtext`; return `label[\tsubtext]` | Empty-glyph leading tab is mandatory for label+subtext rows without icons |
| `omarchy-transcode` ↔ ffprobe/ffmpeg/magick | subprocess argv | ffprobe only on interactive video path; numfmt/stat are coreutils invariants |
| `transcode.py` ↔ `omarchy-transcode` | bare `omarchy-transcode <path>`; prompts run in the spawned terminal | No change required; PR #6698 changes this file (see above) |

## Sources

- `bin/omarchy-transcode` (207 lines, read in full)
- `bin/omarchy-menu-select` (99 lines), `bin/omarchy-menu-input`, `bin/omarchy-menu-file`, `bin/omarchy-shell`
- `shell/plugins/menu/Menu.qml` (1480 lines; `openDmenu` 861–881, `rebuildDmenuDisplay` 553–603, `activateIndex` 759–787, `finishRequest` 117–135, key handling 1154–1160)
- `default/nautilus-python/extensions/transcode.py`
- `test/shell.d/base-test.sh`, `monitor-scaling-test.sh`, `menu-plugin-test.sh`, `menu-test.sh`, `bin-style-test.sh`
- `docs/menu.md` §"Select and input modes"; `agents/skills/command-metadata.md`; `AGENTS.md`
- Upstream diff: `github.com/omacom/omarchy/pull/6698.diff` + `spaceXrace/omarchy@add-folder-transcoding` test file
- `.planning/PROJECT.md` (TRANSC-01…06), `.planning/REQUIREMENTS.md`

---
*Architecture research for: omarchy-transcode quality selection + size estimation*
*Researched: 2026-09-15*
