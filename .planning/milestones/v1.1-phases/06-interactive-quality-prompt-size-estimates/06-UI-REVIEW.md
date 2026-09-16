---
status: complete
phase: 06-interactive-quality-prompt-size-estimates
type: ui-review
audited: 2026-09-16
baseline: "abstract 6-pillar standards + locked contract (06-CONTEXT.md D-01..D-04; bin/omarchy-menu-select glyph⇥label⇥subtext wire format; Menu.qml dmenu renderer)"
screenshots: "not captured — no dev server (ports 3000/5173/8080 closed); the audit surface is a Wayland layer-shell menu, so running-UI evidence comes from 06-UAT.md test 1 (pass, 2026-09-16)"
overall: 22/24
---

# Phase 6 — UI Review

**Audited:** 2026-09-16
**Baseline:** Abstract 6-pillar standards (no UI-SPEC.md exists for this phase) + the locked phase contract: `06-CONTEXT.md` D-01 (`CRF N · ~N MB`), D-02 (per-row `larger than source`), D-03 (all-qualitative fallback, uniform heights), D-04 (empty glyph), and the `bin/omarchy-menu-select` `glyph⇥label⇥subtext` wire contract (`bin/omarchy-menu-select:9-15`).
**Screenshots:** Not captured — no dev server detected (localhost:3000/5173/8080 all closed). This phase's UI surface is a Quickshell/Wayland layer-shell menu, not a web page; per `agents/skills/visual-verification.md` the valid evidence channel is the running desktop, recorded in `06-UAT.md` test 1 (**pass**: cursor on `medium`, `CRF N · ~N MB` subtexts un-elided at ~300px card width, uniform `detailRowHeight`, Enter accepts medium). Code-level verification of the wire format and renderer contract supplements it below.

**Scope note:** The phase diff (`11083223`, `fbe56e4c`) touches only `bin/omarchy-transcode` and two test files — zero QML/frontend changes. The audit surface is therefore (a) correct consumption of the existing menu contract and (b) the visual result that contract produces. Where a pillar has no phase-introduced code to audit, that is stated explicitly rather than manufactured into findings.

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 4/4 | Prompt, labels, and all four subtext families match sibling-prompt conventions and the locked D-01..D-03 wording |
| 2. Visuals | 4/4 | Two-level label/subtext hierarchy inherited from the dmenu renderer; empty-glyph rows keep one visual dialect across the flow (D-04) |
| 3. Color | 3/4 | Subtext keeps `foreground`@0.52 on the cursor row while the label switches to `selectedText` — inherited renderer asymmetry, now the menu's default-open state (Menu.qml:1351-1353) |
| 4. Typography | 4/4 | Two sizes (heading label / bodySmall detail), one weight override; `·` and `~` glyphs verified rendering in the running UI |
| 5. Spacing | 4/4 | Uniform `detailRowHeight` is guaranteed by construction in every state — no mixed detail/no-detail row set is reachable |
| 6. Experience Design | 3/4 | Quality prompt fires before format validity is known for positional formats (`avi` orphan — pinned, not fixed): user answers a prompt whose answer is discarded |

**Overall: 22/24**

---

## Top 3 Priority Fixes

1. **Selected-row subtext ignores `selectedText`** (`shell/plugins/menu/Menu.qml:1351-1353`) — the detail `Text` is hardcoded `color: root.foreground` (opacity 0.52) with no `hasCursor` ternary, unlike the label (:1340), icon (:1298), and trail chevron (:1382). Because `--default-index 1` opens this menu with `medium` already highlighted, the very first thing the user sees is a subtext rendered in the unselected color over `selectedBackground` — in themes where `selectedText` diverges from `foreground` (bright accent selection), the estimate sits at degraded contrast. UAT showed it legible in the tester's theme, so this is theme-dependent, not universal. Fix: `color: row.hasCursor ? root.selectedText : root.foreground` on the detail Text — a one-line change to the shared renderer (this file was untouched by the phase; schedule as a menu-renderer follow-up, not a phase-6 blocker).
2. **Quality prompt precedes format validation for positional formats** (`bin/omarchy-transcode:365-367`) — `omarchy transcode in.mov avi` fires `Select quality` with qualitative rows, takes the user's pick, then fails `Invalid video format`. The interaction is wasted and the error arrives one prompt late. This is pinned in tests (`an unknown format prompts with qualitative rows then fails Invalid video format`) and predates the phase in kind (the resolution prompt already fired before the same failure), but the phase adds a second dead prompt. Fix: gate the prompt on `[[ $format == "mp4" || $format == "gif" ]]` in `main()`, or validate positional `format` up front alongside the existing positional `quality` validation (:334-347).
3. **`~N MB` labels MiB math as "MB"** (`bin/omarchy-transcode:230-238`) — `estimate_label` divides by 1048576 (MiB) but renders `MB`. Direction is honest (understates by ~4.9%, and `~` signals approximation), and the comment (:233) claims MiB matches the completion notification's convention — but the label and the unit disagree, and Phase 7 will put a real byte count in the notification where the mismatch becomes user-comparable. Fix: either render `MiB`, or verify the notification reports the same scale and document the deliberate choice before Phase 7 lands.

---

## Detailed Findings

### Pillar 1: Copywriting (4/4)

Verified against the sibling prompts in the same flow and the locked wording:

- **Prompt:** `Select quality` (`bin/omarchy-transcode:274`) — verb-first title matching `Select format` (:351, :353) and `Select resolution` (:359, :361); renders as `Select quality…` via the header template (Menu.qml:1210). Consistent.
- **Labels:** `high`/`medium`/`low` lowercase — same register as `jpg`/`png`/`mp4`/`gif` and `4k`/`1080p`/`720p` rows. Consistent.
- **Subtexts:** `CRF N · ~N MB` (mp4, D-01 verbatim per ROADMAP), `N fps` (gif, D-00f), `Best quality`/`Balanced`/`Smallest file` (D-03 fallback), `larger than source` (D-02 degrade — rendered as `CRF 18 · larger than source`, keeping the CRF calibration anchor on degraded rows, bin/omarchy-transcode:263). All ≤30 chars, no tabs, honest (`~` + 1–2 sig figs per D-00h — the fake-precision anti-feature is avoided).
- **No generic labels:** no `OK`/`Cancel`/`Submit` patterns; no empty/error strings introduced by the phase. Errors (`Invalid video quality`, :280) match existing stderr style.
- **Minor observations (not score-affecting):** MiB math labeled `MB` — see priority fix 3. Fallback subtexts are sentence-case phrases under lowercase labels — acceptable, they are phrases not values. All mp4 subtexts contain `CRF`, so typing "crf" doesn't narrow the filter; "18" or "fps" does — trivial.

### Pillar 2: Visuals (4/4)

No new visual code — the audit is whether the consumed renderer serves these rows well:

- **Hierarchy:** label at `Style.font.heading` + `Font.Medium` (Menu.qml:1342-1343) over detail at `Style.font.bodySmall` + `opacity: 0.52` (:1353-1355) — a clear two-level structure; the tier is the primary read, the estimate secondary.
- **Dialect consistency (D-04):** rows carry the empty glyph field (`rows+=($'\t'"$tier"$'\t'"$subtext")`, :271), so `hasIcon` is false and `contentColumn` anchors at the standard no-icon inset (:1328-1329) — pixel-identical row shape to the `Select format`/`Select resolution` prompts in the same flow. Icon-ing only this step would have introduced a second dialect; correctly avoided.
- **Focal point:** single three-row list with the cursor pre-parked on `medium` — the recommended choice is where the eye lands.
- **Wire-format correctness:** Menu.qml:569-572 parses `parts[0]` as icon only when a second field exists; the leading tab yields `icon=""`, `label="high"`, `detail="CRF 18 · ~41 MB"` exactly as intended. (A bare `label⇥subtext` would have rendered the label as the icon — the leading tab is load-bearing and present.)
- **Running-UI evidence:** UAT test 1 (pass) confirms cursor on `medium`, subtexts rendered.

### Pillar 3: Color (3/4)

**WARNING.** The phase introduces zero color code; all colors are inherited theme tokens (`Color.menu.*` via root properties, Menu.qml:88-96). One inherited asymmetry becomes user-facing in this menu's default state:

- **Finding:** the subtext `Text` is `color: root.foreground` unconditionally (Menu.qml:1352) while every other row element switches to `selectedText` under cursor (:1298, :1340, :1382). With `--default-index 1`, the `medium` row — the first thing rendered — shows its estimate at `foreground` × 0.52 over `selectedBackground`. UAT test 1 recorded the subtext legible, so the tester's theme keeps enough contrast; the risk is themes where `selectedText` diverges from `foreground`. This is a pre-existing renderer gap (the file is untouched by this phase) that this menu happens to make the default-visible case, which is why it's scored here rather than ignored.

No hardcoded colors, no accent overuse — the bash side contributes text only.

### Pillar 4: Typography (4/4)

- **Sizes in play on the new rows:** `Style.font.heading` (label), `Style.font.bodySmall` (detail), `Style.font.heading` (header prompt) — two distinct sizes, inside the ≤4 budget.
- **Weights:** `Font.Medium` on the label only; detail and header at default weight — one weight override, inside the ≤2 budget.
- **Glyphs:** `·` (U+00B7) and `~` render correctly in the menu font per UAT test 1; `CRF`, `fps`, `MB` are plain ASCII. `textFormat: Text.PlainText` throughout (:1337, :1348) — no markup injection surface from the subtext strings.
- **Elision:** both label and detail `elide: Text.ElideRight` (:1344, :1356). Longest reachable subtext is `CRF 20 · larger than source` (~27 chars) or `CRF 18 · ~110 MB` — far inside the ~220px text column at the default 300px card; UAT confirms un-elided rendering.

### Pillar 5: Spacing (4/4)

- **Uniform row heights by construction:** `rowHeightForDetail` returns `detailRowHeight` whenever a dmenu row has detail (Menu.qml:147-149); the delegate height binds it (:1274). In `select_quality` (:259-272) every reachable state yields three non-empty subtexts: mp4 estimates (`quality_kbps` is all-three-tiers-or-none per resolution arm, :219-222, and `duration` is menu-global — a mixed estimate/qualitative set is unreachable), per-row `larger than source` (still a detail → same height), gif `N fps`, or the all-qualitative D-03 fallback. The mixed-height "looks buggy" pitfall (CONTEXT pitfall 10) is designed out, not just tested.
- **Spacing tokens:** `detailRowHeight = max(space(58), body + caption + rowPaddingX*2)` (:104), `rowSpacing = spacing.xs` (:108), content margins and insets unchanged — the phase consumes the standard scale, adds nothing arbitrary.
- **Card sizing:** default `dmenuWidth` 300 (:61, :872) — subtext column ≈220px after insets/trail; verified un-elided by UAT at ~300px.

### Pillar 6: Experience Design (3/4)

**WARNING.**

- **Finding (the pinned orphan):** `main()` gates the prompt on `[[ $type == "video" && -z $quality ]]` (:365) without checking that `format` is transcodable. A positional `avi`/`webm` reaches `Select quality` (qualitative rows), takes a pick, then dies `Invalid video format` at :144. The wasted prompt is real but bounded (positional-only, undocumented formats); pinned in tests and disclosed in the SUMMARY. Fix = priority 2.
- **Verified good coverage:**
  - **Esc/empty pick:** `omarchy-menu-select` exits 1 on empty selection (:110-113) → `select_quality ... || return` (:274) → silent abort — identical semantics to the format/resolution prompts. Test-pinned (`an empty menu pick aborts before the notification`).
  - **Default-accept:** `dmenuDefaultIndex` clamps `payload.defaultIndex` into range (MenuModel.js:497-503), `openDmenu` seeds `selectedIndex` (Menu.qml:874, :878) — Enter reproduces positional `medium` byte-for-byte (SUMMARY D1).
  - **Probe failure:** every ffprobe/stat call is `|| true`- or `if`-guarded and regex-gated before `awk -v` (:162-178, :252-256) — hiccups degrade cosmetically to D-03 rows, never abort under `set -euo pipefail`. Test-pinned for `N/A` and hard-fail.
  - **Honest degradation:** per-row `larger than source` past `stat -c %s` (:232) — the estimate is suppressed exactly where it would lie.
  - **Return sanitization:** `label⇥subtext` return stripped at first tab and re-validated `high|medium|low` inside the helper (:276-283) — a foreign label dies before the notification boundary.
  - **Filter:** dmenu filter matches label AND detail (Menu.qml:573-574); typing resets the default highlight (intentional, MenuModel.js:493-496).
- **Minor note (not score-affecting):** no busy affordance between the resolution pick and the quality menu while ffprobe runs — typically <100ms on local media, potentially longer on network sources. The dmenu contract has no spinner; noted for the record only.
- **Nautilus multi-file:** prompt-per-file verified by UAT test 3 (locked behavior, working).

---

## Files Audited

- `bin/omarchy-transcode` — `select_quality` (:247-285), helpers `video_duration`/`video_audio_kbps`/`quality_token`/`quality_kbps`/`estimate_label` (:162-240), `main()` gate (:365-367), usage (:14-32)
- `bin/omarchy-menu-select` — wire contract (:9-15), `--default-index` arm (:54-61), payload assembly (:86-102), empty-selection exit (:110-113)
- `shell/plugins/menu/Menu.qml` — `rebuildDmenuDisplay` row parse (:554-604), `rowHeightForDetail`/`detailRowHeight` (:104, :147-149), `dmenuDefaultIndex`/`openDmenu` (:864-885), row delegate label/detail/cursor rendering (:1252-1409), filter-on-detail (:573-574), `label⇥detail` return (:771)
- `shell/plugins/menu/MenuModel.js` — `dmenuDefaultIndex` clamp (:493-503)
- `bin/omarchy-menu-plugin` — prior multi-field precedent `icon⇥name⇥id` (:25-36), confirming the empty-glyph variant is the contract's documented first field
- `test/shell.d/transcode-quality-test.sh` — dual-mode `omarchy-menu-select` stub (:63-78), argv assertions pinning `$'\ttier\tCRF N · ~N MB'` rows and `--default-index 1` (:366-379, :430-447)
- `.planning/phases/06-interactive-quality-prompt-size-estimates/` — 06-CONTEXT.md (D-01..D-04), 06-01-PLAN.md, 06-01-SUMMARY.md, 06-UAT.md (running-UI evidence)

**Not audited (out of surface):** no `components.json` → registry safety audit skipped (NO_SHADCN); no `UI-SPEC.md` → abstract standards baseline; Menu.qml/MenuModel.js read as contract references only — unchanged by this phase.
