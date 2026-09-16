# Phase 7 Research: Completion-size notification + docs

**Researched:** 2026-09-16
**Requirements:** SIZE-02
**Confidence:** HIGH — the 383-line target file, `bin/omarchy-notification-send`, the full stub harness, `test/cli`'s metadata checks, and every doc surface that mentions transcode were all read end-to-end this session. `numfmt`'s output shapes, `stat` pipeline-failure semantics under `pipefail`, and the two glyph bytes were **executed and verified live** in this environment.
**Scope:** HOW to implement. WHAT is locked by REQUIREMENTS.md SIZE-02 ("The completion notification reports the actual output file size") and ROADMAP Phase 7's two success criteria. **No CONTEXT.md exists for this phase** — constraints below are reconstructed from requirements, ROADMAP, AGENTS.md conventions, and Phase-5/6 precedent; the two Phase-6 review advisories are analyzed in §7 and flagged as planner/user decisions, not locked.

---

<user_constraints>
## User Constraints (no CONTEXT.md — derived)

Carried forward (locked by requirements / prior phases — not re-decided):

- **SIZE-02 text (verbatim):** "The completion notification reports the actual output file size." ROADMAP example format: `38 MB`.
- **Both paths:** the done notification fires for video (:375) and picture (:379) transcodes — SIZE-02 covers both call sites.
- **`omarchy-notification-send`, never `notify-send`** (AGENTS.md Helper Commands); reuse the existing glyphs (new glyphs need the icon-font skill — PITFALLS integration gotchas).
- **Atomic commits** (AGENTS.md Git): Phase 5 precedent = script + test + docs in one `feat` commit; Phase 6 precedent = a separate `test()` commit when a stale pin must move to keep every commit green.
- **PR #6698-safe placement:** new helpers go between `copy_to_clipboard` (ends :156) and `main` (:287) — the proven conflict-free slot; the main() tail itself (:369–380) is inside the PR's conflict zone, so diffs there should stay minimal.
- **Probe discipline under `set -euo pipefail`:** every new subprocess call is `|| true`-/`if`-guarded and regex-gated before use (Phase-6 idiom; PITFALLS pitfall 8).
- **No re-litigating:** tier tables, subtext formats, dedupe policy, prompt ordering — all shipped and pinned.

### The agent's Discretion

- Exact notification wording/punctuation carrying the size (`(38 MB)` suffix vs `·` separators vs filename inclusion — §6)
- Helper vs inline stat/format (recommendation: a small helper — both call sites need it)
- Unit label on the actual size (`38 MB` MiB-scale vs `38MiB`/`40MB`) — **decision flagged, §7b**
- Whether to fold the two Phase-6 advisories into this phase — **decision flagged, §7**
- Whether the encoder stubs gain an output-creating knob or `stat` is stubbed — recommendation in §5

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SIZE-02 | The completion notification reports the actual output file size | §1 (exact call sites), §2 (verified size-formatting incantations), §3 (notification argv contract), §5 (stub gap + assertion matrix), §6 (edge cases — the notification must never lie) |

ROADMAP success criterion 2 — "usage(), `# omarchy:*` metadata, `docs/`, and `manual/` entries are consistent with the shipped behavior (test/cli metadata shape stays green)" — is a docs sweep, not a feature; §4 enumerates every surface with current sync status.

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Actual output size capture + humanize | `bin/omarchy-transcode` (one new helper in the safe slot, or inline) | coreutils `stat`/`numfmt` or awk | Output path is already resolved in `$output`; no other component can see it |
| Done-notification body carrying the size | `bin/omarchy-transcode` main() tail (:375, :379) | — | Two call sites, one body string — interpolate once per arm or hoist a shared body |
| Docs/metadata consistency | `manual/12-screenshots-recording.md`, `bin/omarchy-transcode` header/usage | `default/agents/skills/omarchy/capture.md`, `docs/` | §4 inventory — most surfaces already synced by Phases 5–6; only the manual needs real edits |
| Nothing else | — | — | No `Menu.qml`, `omarchy-menu-select`, `transcode.py`, router, or keybinding changes — the notification change is script-local |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `stat -c %s` | coreutils | Byte size of the finished output | Already used on the input at `bin/omarchy-transcode:254`; platform invariant |
| awk | system (gawk) | `bytes/1048576` → `"%.0f MB"` | Repo float convention; produces the requirement's `38 MB` shape (space + fixed unit) that numfmt **cannot** — see §2 verified outputs |
| `numfmt --to=iec*` | coreutils | Alternative humanizer — verified shapes: `38M` / `38MB` / `38MiB` / `40MB` | Only if the planner picks a numfmt-native label (§7b); it cannot emit `38 MB` with the space |
| `omarchy-notification-send` | repo | Done notification | Contract verified at `bin/omarchy-notification-send:85-115` — §3 |

### Supporting

None — zero new dependencies, zero new helpers beyond at most one `output_size_label()`-style function.

**Installation:** none — `stat`, `numfmt`, `awk` all verified on disk (`/usr/bin/stat`, `/usr/bin/numfmt`, `/usr/bin/awk`); numfmt output shapes executed live this session.

## Package Legitimacy Audit

N/A — installs nothing.

---

## 1. Exact edit surface in `bin/omarchy-transcode`

File anatomy (verified this session, post-Phase-6): header `:3-7`, `usage()` `:11-33`, `media_type()` `:35-47`, `output_path()` `:49-73`, `transcode_picture()` `:75-105`, `transcode_video()` `:107-148`, `copy_to_clipboard()` `:150-156`, six Phase-6 helpers `:158-285`, `main()` `:287-381`, `main "$@"` `:383`.

### 1a. The two done-notification call sites

```bash
# main() tail, lines 371-380 — CURRENT:
  if [[ $type == "video" ]]; then
    omarchy-notification-send -g  "Transcoding video…" "$(basename -- "$input") to $format ($resolution)"   # :372 start — UNCHANGED
    transcode_video "$input" "$format" "$resolution" "$output" "$quality"                                  # :373
    copy_to_clipboard "$output"                                                                            # :374
    omarchy-notification-send -g  "Transcoded to $resolution $format" "Saved and copied to clipboard."     # :375 ← SIZE-02
  else
    transcode_picture "$input" "$format" "$resolution" "$output"                                           # :377
    copy_to_clipboard "$output"                                                                            # :378
    omarchy-notification-send -g  "Transcoded to $resolution $format" "Saved and copied to clipboard."     # :379 ← SIZE-02
  fi
```

The two glyph bytes (PUA, rendered blank above): `:372`/`:375` use `EF 80 BD` = U+F03D `` (video); `:379` uses `EF 80 BE` = U+F03E `` (image) — verified via `cat -A` (`M-oM-^@M-=` / `M-oM-^@M->`). Reuse them verbatim.

### 1b. Recommended minimal diff (per-arm, inside the known PR #6698 zone — keep it small)

Add one helper in the proven safe slot (below `copy_to_clipboard`, with the Phase-6 helpers):

```bash
# Human-readable size of a finished output ("38 MB"), or fails when stat
# cannot read it -- callers degrade the notification body rather than lie.
output_size_label() {
  local bytes
  bytes=$(stat -c %s "$1" 2>/dev/null || true)
  [[ $bytes =~ ^[0-9]+$ ]] || return 1
  awk -v b="$bytes" 'BEGIN { printf "%.0f MB", b / 1048576 }'
}
```

Then each done-notification arm gains two tokens' worth of change:

```bash
    copy_to_clipboard "$output"
    size=$(output_size_label "$output" || true)
    omarchy-notification-send -g  "Transcoded to $resolution $format" \
      "Saved and copied to clipboard${size:+ ($size)}."
```

`${size:+ ($size)}` expands to ` (38 MB)` when the label exists and nothing when stat failed — the degrade is one expansion, no `if` tree. Add `size` to `main()`'s `local` line (:289).

**Alternative the planner may prefer:** hoist the body construction once after the `if`/`else` by factoring the done notification out of both arms (`glyph` per arm, shared body). That *restructures* the main() tail — a bigger diff in exactly the region PR #6698 rewrites (ARCHITECTURE.md:158). **Recommend the per-arm minimal form above.**

### 1c. Ordering: stat before or after `copy_to_clipboard`?

Behaviorally equivalent — a `wl-copy` failure aborts the script under `set -e` before the done notification either way (same as today). The PITFALLS gotcha ("keep actual-size collection before or independent of clipboard so notification still fires") means only that **stat itself must not kill the notification** — the `|| true` + regex gate handles that. Compute it right before the notification call (after encode + copy) so the file provably exists on the happy path.

## 2. Size formatting — verified output shapes

Executed live this session on `39845888` bytes (38.00 MiB):

| Incantation | Output | Verdict |
|-------------|--------|---------|
| `numfmt --to=iec` | `38M` | Wrong shape — no `B`, no space |
| `numfmt --to=iec --suffix=B` | `38MB` | Close; no space (requirement example has one) |
| `numfmt --to=iec-i --suffix=B` | `38MiB` | Honest binary unit; visually inconsistent with `~41 MB` estimates |
| `numfmt --to=si --suffix=B` | `40MB` | True SI MB but **different scale** from the MiB-scaled estimates |
| `numfmt --to=iec-i --suffix=' B'` | `38Mi B` | Garbage — suffix lands after the unit letter |
| `numfmt --to=iec-i --format='%.0f MB'` | `38Mi MB` | Garbage — format prints the scaled mantissa then the unit anyway |
| `awk -v b=… 'BEGIN{printf "%.0f MB", b/1048576}'` | `38 MB` | **Exact requirement shape AND same MiB scale as the Phase-6 estimates** |

**Recommendation: awk `"%.0f MB"` on the MiB scale.** Rationale: (a) produces `38 MB` verbatim from the ROADMAP example; (b) the estimate→actual calibration loop needs same-scale numbers — `~41 MB` estimate vs `38 MB` actual compares apples-to-apples; (c) no GB rollover — a 1.4 GiB output reads `1400 MB`, matching the estimate convention (`~1200 MB`); (d) awk is the repo's float convention already used by `estimate_label` two helpers up.

**`pipefail` trap verified live:** `size=$(stat -c %s "$output" | numfmt …)` — when `stat` fails the pipeline's status is nonzero → the assignment fails → `set -e` **aborts the script** (empty `numfmt` input is NOT the problem; `numfmt` on empty stdin exits 0). The two-step form (`bytes=$(stat … || true)` then gate) is required — same pattern `select_quality` uses at `:254-255`.

## 3. `omarchy-notification-send` argv contract

Verified at `bin/omarchy-notification-send` (full read):

- Options parse in a loop (:85-91) until the first non-option; `headline=$1`, then the next positional is `description` **even if dash-leading** (`known_flag` gate at :104-115 — a body like `-50% off` is taken as text). `-g <glyph>` sets the `omarchy-glyph` hint (:60, :154-156); `-u` defaults to `low` urgency (:12).
- The script calls `busctl … Notify susssasa{sv}i` directly — headline and body are typed strings; nothing in the body can be reinterpreted as options (:184-194 comment block explains the anti-injection design).
- **No title/body schema constraint** — the body is free text; `(38 MB)` parenthetical, `·` separators, or a filename all work. Existing transcode calls already pass `-g <glyph> "<headline>" "<body>"`.
- The harness stub records `notification: $*` — headline and body land on one greppable line (§5).

## 4. Docs/metadata sync inventory — every surface, current status

| Surface | Location | Status | Phase-7 action |
|---------|----------|--------|----------------|
| `# omarchy:group/name/summary/args/examples` | `bin/omarchy-transcode:3-7` | ✅ synced — `args=` already reads `[--path path] [input] [format] [resolution] [quality]`; `examples=` already includes `…mp4 1080p low` | Verify only; `test/cli` keeps it green |
| `usage()` | `bin/omarchy-transcode:11-33` | ✅ synced — :17 "…resolution, and for videos the quality", `Qualities:` block :30-31 | Verify only — usage documents args, not notifications; nothing about size belongs here |
| Agent skill doc | `default/agents/skills/omarchy/capture.md:59` | ✅ synced — signature already has `[quality]` (Phase 5) | Verify only (optional: could note size-in-notification; not required — it's a signature reference) |
| End-user manual | `manual/12-screenshots-recording.md:70` | ⚠️ **STALE** — "then asks for a format and a size" omits the video quality step shipped in Phase 6 | Edit: mention the quality step AND the done-notification size in the :70-72 paragraph; keep user-voiced, no CRF jargon (Phase-5 precedent) |
| End-user manual | `manual/12-screenshots-recording.md:72,74` | ✅ synced — naming + quality-suffix sentences accurate | Fold into the same paragraph edit if wording flows |
| `docs/` tree | — | ✅ **zero transcode mentions** (grep-verified) — `docs/notifications.md` documents the send mechanism, not callers | Nothing to change; the ROADMAP criterion is satisfied by the negative. Note it in the plan so nobody hunts |
| Router group text | `bin/omarchy:89` `GROUP_DESCRIPTIONS[transcode]` | ✅ "Image and video transcoding" — still accurate | None |
| Invocation surfaces | `default/omarchy/omarchy-menu.jsonc:69`, `default/hypr/bindings/utilities.lua:87`, `default/nautilus-python/extensions/transcode.py` | ✅ no arg/doc text to sync | None |
| Other manual mentions | `manual/41-branding.md:39,42` (transcode-ascii), `manual/07-hotkeys.md:79` ("Transcode media") | ✅ different subcommand / accurate one-liner | None |

**`test/cli` constraints (verified :598-612):** the suite only checks metadata *shape* — `summary=` present, `args=` non-empty, no removed keys (`legacy/usage/visibility/mutates/interactive`), no `requires-sudo=false`. No metadata edits are even needed; the gate stays green by construction.

## 5. Test strategy — extend `test/shell.d/transcode-quality-test.sh`

The harness already stubs `omarchy-notification-send` — `printf 'notification: %s\n' "$*" >>"$CALLS"` at `:47-50` — so **notification argv capture exists**; the done-notification body is one greppable `notification: -g <glyph> Transcoded to … Saved and copied to clipboard (38 MB).` line.

### 5a. The one real gap: encoder stubs never create the output

`:27-30` documents why: "They never create the output file: realpath tolerates a missing final component, and a stub touch would leak files into $TMPDIR and make dedupe rows self-collide." So today `stat -c %s "$output"` in the new code would *always* fail under the harness — the size path would be untestable.

**Recommended fix — opt-in output knob on the shared ffmpeg/magick stub** (same dual-mode pattern as `FAKE_PICK`):

```bash
# inside the :30-40 stub body, after the argv recording
if [[ -n ${FAKE_OUT_BYTES:-} ]]; then
  truncate -s "$FAKE_OUT_BYTES" "${!#}"
fi
```

- Unset → status quo (dedupe rows unaffected, degrade path exercised).
- Set → real file, real `stat`, real `awk` — the notification carries a real computed size.
- Rows that set it own the created file and `rm -f` it after asserting — the harness's stated fixture-ownership convention (:112-114 comment).

Alternative considered: stub `stat` itself — rejected; `stat` is already legitimately used on the *input* (`src_bytes` at :254), so a blanket stub would need path dispatch and would prove less (the real stat+awk chain stays unexercised).

**Second optional knob — `FAKE_ENCODE_RC`:** `exit "${FAKE_ENCODE_RC:-0}"` at the stub's end lets one row prove the failure path: encoder nonzero → run fails → **zero `Transcoded` notification lines** (the notification cannot lie because it never fires). ~1 line of stub, high-value pin for the "no output file → no size claim" edge.

### 5b. Assertion matrix

| # | Invocation | Assert | Covers |
|---|-----------|--------|--------|
| Video done-notification size | `FAKE_OUT_BYTES=39845888 run_transcode in.mov mp4 1080p medium` | `notification:` line contains `clipboard (38 MB)` (or the locked format); then `rm -f` the created output | SIZE-02 video |
| Picture done-notification size | `FAKE_OUT_BYTES=39845888 run_transcode img.png jpg medium` | same `38 MB` body on the picture arm | SIZE-02 picture |
| gif done-notification size | `FAKE_OUT_BYTES=… run_transcode in.mov gif 720p low` (or fold into the video row) | size present on the gif arm too — same code path, cheap pin | SIZE-02 gif |
| Degrade, never lie | run WITHOUT `FAKE_OUT_BYTES` (any existing row's tail) | `notification:` line has `Saved and copied to clipboard.` and **no** `(` size parenthetical | SIZE-02 honesty |
| Encode failure | `FAKE_ENCODE_RC=1 run_transcode in.mov mp4 1080p medium` | run exits nonzero; zero `Transcoded` lines in `$calls` (the `Transcoding` start line exists — orphan is pre-existing behavior, pin it or don't assert on it) | failure path |
| Deduped output still sized | pre-create `in-1080p.mp4` + `FAKE_OUT_BYTES=…` → dedupes to `-2`; notification still carries the size; `rm -f` both | SIZE-02 + SAFE-01 interaction |
| (If WR-01 folded in) | `FAKE_DURATION=18` @ `720p` | rows pin `~6`/`~4`/`~2 MB` — catches `%d` flooring (unfixed renders `~5`/`~3`/`~1`) — **recompute at plan time** | advisory |
| Docs/metadata | `./test/cli` | metadata shape green (no edits needed) | ROADMAP SC2 |

Existing-notification rows keep passing: the recorded `notification:` lines gain a body suffix but nothing greps the old body verbatim — verified, no current assertion matches `Saved and copied to clipboard` literally.

### 5c. Pre-existing harness flaw worth one line (optional)

06-REVIEW IN-06: `notify_line=$(grep -n 'Transcoding' …)` is empty when the line is absent and `(( notify_line < ffmpeg_line ))` then false-passes on `0 < N` (`test/shell.d/transcode-quality-test.sh:192-195`). A `[[ -n $notify_line && -n $ffmpeg_line ]] || fail …` guard fixes it — cheap while extending the file; planner's call whether it rides in the feat commit or a `test(07)` commit (Phase-6 `fbe56e4c` precedent argues for separate).

## 6. Edge cases — the notification must never lie

| Edge | Behavior | Mechanism |
|------|----------|-----------|
| **Encode failure** | No done notification at all — cannot lie | `set -e` aborts inside `transcode_video`/`transcode_picture` before :375/:379. The video path's *start* notification orphans — **pre-existing** behavior, not Phase-7 scope |
| **stat failure / output vanished** | Body degrades to plain `Saved and copied to clipboard.` | `output_size_label` returns 1 → `size=""` → `${size:+ …}` expands empty; run still exits 0 |
| **Deduped output (`-2`/`-3`)** | Size reports the *actual written file* | `$output` already holds the deduped path (`output_path` resolved at :369 pre-notification) — stat is correct by construction |
| **gif vs mp4 vs picture** | Uniform — same tail code, picture arm uses  glyph | One helper serves both arms |
| **0-byte output** | `0 MB` — honest | `[[ $bytes =~ ^[0-9]+$ ]]` accepts `0`; awk prints `0 MB` |
| **`avi` orphan** | Unchanged — start notification fires, `Invalid video format` dies post-notification, no done notification | pre-existing pinned orphan; size code unreachable on that path |
| **Body wording** | Minimum: `Saved and copied to clipboard (38 MB).` Optional upgrade per PITFALLS UX row ("Done notification omits the filename or size"): `clip-1080p.mp4 · 38 MB, saved and copied to clipboard.` — helps Nautilus multi-file where notifications stack | Planner decision; requirement only mandates the size |
| **`(( ))` status-1-on-zero** | Not triggered — no `(( ))` on stat output; the regex gate runs first | PITFALLS pitfall 8 idiom |

## 7. The two Phase-6 advisories — fold in or defer? (DECISION for planner/user)

### 7a. WR-01: `estimate_label` `%d` floors sub-10 MiB estimates (`bin/omarchy-transcode:238`)

- **Fix:** `printf "~%d MB", r` → `printf "~%.0f MB", r` — one character. `%.0f` rounds; `%d` truncates. Verified by review: 1.9 MiB → `~1 MB` today vs `~2 MB` fixed (~48% understatement at the floor).
- **Blast radius:** all nine currently pinned estimate strings are ≥10 (`~41/~23/~11`, `~110/~60/~30`, `~39/~21/~10`) → **zero existing test changes**; add one sub-10 pin (§5b) to prove the fix.
- **Cost/benefit:** ~1-line code change + ~10-line test block. Benefit: the milestone shouldn't close with a known understatement bug sitting exactly in the estimate→actual loop Phase 7 is closing.
- **Recommendation: FOLD IN as a separate `fix(07)` commit** — not inside the `feat(07-01)` commit (atomic-commit rule: estimate rounding is a distinct concern from notification size). Phase-6's `fbe56e4c` is the precedent for a small scoped companion commit.
- Alternative: defer to milestone cleanup — cheap either way, but there is no milestone cleanup phase left.

### 7b. MB-vs-MiB terminology (UI-REVIEW advisory)

- **Facts:** `estimate_label` divides by `1048576` (MiB) but prints `MB` (`:233-238`); verified numfmt shapes in §2.
- **Options:**
  - **(a) Keep `MB` label, MiB scale, for both estimate and actual** (awk `"%.0f MB"`) — `~41 MB` → `38 MB` compares cleanly; matches the requirement's example verbatim; loose-but-universal consumer usage (every OS file manager says "MB" for MiB).
  - **(b) `MiB` everywhere** — `numfmt --to=iec-i --suffix=B` → `38MiB`; most honest; churns all nine Phase-6 pinned strings + subtext width; `MiB` is jargon in an end-user notification.
  - **(c) True SI `MB` everywhere** — estimate math switches to `/1e6` and actual to `numfmt --to=si --suffix=B` → `40MB`; honest *and* consistent, but churns every pinned estimate value and drops the space.
- **Recommendation: (a)** — Phase 7 is *forced* to pick a label for the notification; picking the MiB-scale `38 MB` resolves the advisory by making both numbers consistently-scaled under one label. Document the choice in the plan; if the user wants strict units, (b)/(c) are bigger diffs best done as their own commit anyway.
- **Decision needed before implementation** — it pins the notification body format that tests assert on.

## Common Pitfalls (phase-scoped)

1. **`set -e`/`pipefail` turns a stat hiccup into a silent abort** — never `$(stat … | numfmt)` bare; two-step `|| true` + `=~ ^[0-9]+$` gate (verified live §2). [PITFALLS pitfall 8]
2. **Notification lies on failure** — automatic (notification sits after encode under `set -e`), but *pin it* with the `FAKE_ENCODE_RC` row so a future refactor can't reorder it. [§6]
3. **Stub-created outputs self-collide dedupe rows** — opt-in `FAKE_OUT_BYTES` knob + `rm -f` ownership, never unconditional `touch` (the :27-30 comment explains why). [§5a]
4. **`numfmt` cannot render `38 MB`** — every numfmt form verified to produce `38M`/`38MB`/`38MiB`/`40MB`, none with the space; awk is the tool. [§2]
5. **Docs sweep misses a stale surface** — the one real stale surface is `manual/12:70` ("asks for a format and a size" — now three prompts for video). `docs/` is verifiably empty of transcode mentions. [§4]
6. **New notification glyph** — reuse  / ; glyph additions route through the icon-font skill. [PITFALLS integration gotchas]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| `38 MB` rendering | `numfmt` + sed/`--format` gymnastics | awk `printf "%.0f MB", b/1048576` | numfmt verified incapable of the spaced fixed-unit form (§2); awk is already the repo's float tool |
| Size capture | `du -h`, `ls -l` parsing, `wc -c` | `stat -c %s` | Already the file's own incantation at :254; byte-exact, no unit ambiguity |
| Notification | `notify-send` | `omarchy-notification-send` | AGENTS.md mandate; D-Bus argv safety (bin/omarchy-notification-send:184-194) |
| Conditional body text | `if`/else duplicating the whole send call | `${size:+ ($size)}` expansion | One call site stays one call site — minimal diff in the PR #6698 zone |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The stub ffmpeg/magick can create a sized output via `truncate -s` without breaking existing rows when the knob is unset | §5a | Low — the unset path is byte-identical to today; the knob is additive |
| A2 | `omarchy-notification-send`'s stub recording shape (`notification: $*`) is the right assertion surface | §5 | None — verified in the harness |
| A3 | Requirement example `38 MB` implies the spaced `N MB` format, matching the `~N MB` estimate convention | §2 | If the planner/user picks `38MB` or `38MiB` instead, only the awk printf and test pins change |
| A4 | No CONTEXT.md for this phase is intentional (phase is small enough to run requirements+research only) | header | If a CONTEXT appears later with locked wording, re-check §6 body-format choice |

## Open Questions (for the planner, all carry recommendations)

1. **Fold in WR-01 (`%d`→`%.0f`)?** Recommend yes, separate `fix(07)` commit (§7a).
2. **Unit label: `38 MB` (MiB scale) vs `38MiB` vs `40MB` (SI)?** Recommend `38 MB` MiB-scale — resolves the terminology advisory by consistency (§7b).
3. **Body wording: `(38 MB)` suffix vs filename-in-body?** Recommend minimal `Saved and copied to clipboard (38 MB).`; filename is a small optional upgrade (§6).
4. **Fix IN-06 false-pass while extending the harness?** Recommend yes in the same or a `test(07)` commit (§5c).
5. **One plan or two?** All work fits one plan comfortably (script + harness + docs ≈ Phase-5 scope); if advisories fold in, they're commits within the same plan, not separate plans.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `stat -c %s` | size capture | ✓ coreutils | — | degrade to plain body (by design) |
| awk | `N MB` render | ✓ `/usr/bin/awk` | system | — |
| `numfmt` | *(alternative only)* | ✓ `/usr/bin/numfmt` | coreutils | awk recommended |
| `omarchy-notification-send` | done notification | ✓ repo | — | — |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash harness — `test/shell.d/*-test.sh` + `base-test.sh` `pass`/`fail`; PATH-shadowing stub binaries; per-invocation env knobs (`FAKE_*`) |
| Config file | none — `test/shell` auto-discovers `*-test.sh` |
| Quick run command | `bash test/shell.d/transcode-quality-test.sh` |
| Full suite command | `./test/shell` and `./test/cli` (or `./test/all`) |
| Estimated runtime | ~5 s (no real encodes) |

### Testability Dimensions

| Dimension | Assessment |
|-----------|------------|
| Notification argv | Already captured by the existing `omarchy-notification-send` stub → `notification:` lines in `$CALLS` |
| Real output size | Needs the `FAKE_OUT_BYTES` stub knob — output files are deliberately never created today (§5a) |
| Failure path | Needs `FAKE_ENCODE_RC` stub knob (1 line) to prove the done notification never fires on encode failure |
| Degrade path | Free — every existing row (no `FAKE_OUT_BYTES`) exercises it once the code lands |
| Docs consistency | `test/cli` covers metadata shape; manual/usage wording is human-reviewed (no doc-content pinning precedent in the repo) |
| Notification rendering in running UI | Manual-only (glyph + body text on a real toast) per `agents/skills/visual-verification.md` |

### Phase Requirements → Test Map

| Req ID | Behavior | Suggested Test ID | Test Type | Automated Command | File Exists? |
|--------|----------|-------------------|-----------|-------------------|--------------|
| SIZE-02 | Video done-notification body carries the real output size (`38 MB`) | `T-07-size-video` | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` — §5b row 1 | ✅ (extend) |
| SIZE-02 | Picture done-notification body carries the size (arm) | `T-07-size-picture` | e2e (stub) | §5b row 2 | ✅ (extend) |
| SIZE-02 | gif arm covered by the same code path | `T-07-size-gif` | e2e (stub) | §5b row 3 (or folded into row 1) | ✅ (extend) |
| SIZE-02 | stat failure / missing output degrades the body — never lies, never aborts | `T-07-degrade` | e2e (stub) | §5b row 4 | ✅ (extend) |
| SIZE-02 | encode failure → zero `Transcoded` notification lines | `T-07-failure` | e2e (stub) | §5b row 5 (`FAKE_ENCODE_RC`) | ✅ (extend) |
| SIZE-02 | deduped `-2` output still reports its size | `T-07-dedupe-size` | e2e (stub) | §5b row 6 | ✅ (extend) |
| ROADMAP SC2 | `usage()`/`# omarchy:*`/`docs/`/`manual/` consistent with shipped behavior | `T-07-docs` | suite + review | `./test/cli` (metadata shape); grep + eyeball for `manual/12:70` | — |
| SIZE-02 (partial) | Real toast shows the size legibly | `T-07-uat` | manual-only | UAT — see below | — |
| *(advisory, if folded)* | sub-10 MiB estimates round, not floor | `T-07-wr01` | e2e (stub) | §5b row 7 | ✅ (extend) |

### Sampling Rate

- **Per task commit:** `bash test/shell.d/transcode-quality-test.sh` and `bash -n bin/omarchy-transcode`
- **Per wave merge:** `./test/shell` and `./test/cli`
- **Phase gate:** full suite green before `/gsd-verify-work`, excluding the 7 documented pre-existing environmental failures (STATE.md — reproduce at base commit `41b7ea3d`; don't chase them)

### Wave 0 Gaps

- [ ] None — the harness exists and is extended in place; the two stub knobs land with the first task, not as prerequisites

### Manual-Only Verifications

| Behavior | Req | Why manual |
|----------|-----|------------|
| Done toast in the running UI shows the size legibly (glyph intact, no truncation) | SIZE-02 | Rendering is a running-UI property per `agents/skills/visual-verification.md`; the dev shell loads the packaged `/usr/share/omarchy` tree — likely end-of-phase UAT like Phase 2/6 |
| Estimate→actual sanity on one real clip (`~N MB` vs the reported `N MB`) | SIZE-02 | Requires a real encode; the calibration loop is the feature's point — one dogfood run, non-blocking (Phase-6 UAT item b already covers the comparison habit) |
| `manual/12` wording reads naturally to an end user | SC2 | Doc prose — human judgment |

## Security Domain

Local bash CLI; no auth/session/crypto surface. Only input-validation-adjacent notes:

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V5 Input Validation | yes | `stat` output regex-gated `^[0-9]+$` before it reaches `awk -v` — same contract as Phase-6 probes; `awk -v` C-escape interpretation is neutralized by the digit-only gate |
| V2/V3/V4/V6 | no | — |

| Threat pattern | Mitigation |
|----------------|------------|
| Output path under attacker-influenced directory | Already bounded — `output_path` derives from `basename`/`dirname` of the input; stat reads a path the script itself computed |
| Notification body as injection vector | Body is a typed D-Bus string via busctl (bin/omarchy-notification-send:184-194); a size string is digits + literal ` MB` regardless |
| stat TOCTOU (file swapped between encode and stat) | Benign — worst case reports the swapped file's size; no write occurs |

## Atomic-Commit / Upstream-PR Plan

| Commit | Contents | Rationale |
|--------|----------|-----------|
| `feat(07-01)` | `bin/omarchy-transcode` (helper + two arm edits) + `transcode-quality-test.sh` (stub knobs + §5b rows) + `manual/12-screenshots-recording.md` | Phase-5 precedent: script + test + docs are one reviewable, independently revertible unit — a candidate upstream PR |
| `fix(07)` *(if WR-01 folds in)* | `estimate_label` `%.0f` + sub-10 pin | Distinct concern; keeps the feat commit's `--stat` clean (Phase-6 `fbe56e4c` precedent for scoped companion commits) |
| `test(07)` *(optional)* | IN-06 false-pass guard | Only if the planner keeps it out of the feat commit |

Upstream-PR hygiene: the whole feature diff is inside `bin/omarchy-transcode` + test + one manual paragraph; no new deps; the helpers stay in the `copy_to_clipboard`→`main` slot that dodges PR #6698's insertion zone; the main()-tail edit is in the PR's known-conflict region and should stay minimal per §1b.

## Sources

### Primary (HIGH confidence — read/executed this session)

- `bin/omarchy-transcode` (383 lines, full read — notification call sites `:372/:375/:379`, helper slot `:157-285`, `output` resolution `:369`, stat-on-input precedent `:254`)
- `bin/omarchy-notification-send` (211 lines, full read — positional contract `:85-115`, busctl argv-safety `:184-194`, glyph hint `:154-156`)
- `test/shell.d/transcode-quality-test.sh` (561 lines, full read — notification stub `:47-50`, no-output-creation comment `:27-30`, encoder stub `:30-40`, `run_transcode` `:114-123`, fixture-ownership convention `:112-114`, IN-06 site `:192-195`)
- `test/cli` metadata checks `:598-612`; `test/shell.d/base-test.sh` `pass`/`fail`
- `manual/12-screenshots-recording.md` (full read — stale `:70`, accurate `:72/:74`); `default/agents/skills/omarchy/capture.md:59`; `bin/omarchy:89`
- Executed live: `numfmt --to=iec[‑i]`/`--to=si`/`--suffix`/`--format` output shapes; `stat|numfmt` pipefail semantics; glyph bytes via `cat -A`
- grep sweeps: `docs/` zero transcode mentions; `manual/` (6 hits), `default/` (10 hits), `agents/` (0 hits) — full inventory in §4
- `.planning/REQUIREMENTS.md` (SIZE-02 verbatim), `ROADMAP.md` Phase 7, `STATE.md` (advisories `:102-103`), `AGENTS.md`, `agents/skills/command-metadata.md`
- `.planning/phases/06-*/{06-01-SUMMARY,06-REVIEW,06-RESEARCH,06-VALIDATION}.md`, `05-*/{05-01-SUMMARY,05-RESEARCH}.md`, `.planning/research/{ARCHITECTURE,STACK,PITFALLS,FEATURES}.md`

### Secondary / not executed

- Real `omarchy-notification-send` on a live bus — dev shell limitation documented in STATE.md; UAT item, not a blocker

## Metadata

**Confidence breakdown:**
- Call sites, argv contract, docs inventory: HIGH — every line ref verified in source this session
- Formatting incantations: HIGH — executed live, not assumed
- Test-harness extension points: HIGH — stub knobs mirror the proven `FAKE_PICK`/`FAKE_DURATION` pattern
- Advisory scope decisions: flagged for planner/user (§7) — analysis complete, choice open

**Research date:** 2026-09-16
**Valid until:** 2026-10-16 (stable — all contracts in-repo; only the notification body wording is an open decision)

---
*Research for: 07-completion-size-notification-docs*
