# Phase 9 Research: Interactive `Custom size…` row

**Researched:** 2026-09-17
**Requirements:** MENU-02
**Confidence:** HIGH — `bin/omarchy-transcode` (645 lines) and `test/shell.d/transcode-quality-test.sh` (1216 lines) read end-to-end at HEAD `7847d99e`; the focused suite runs green (82/82) in this session. `bin/omarchy-menu-input` (58 lines), `bin/omarchy-menu-select` (120 lines), the `Menu.qml` input/select paths, and `MenuModel.dmenuDefaultIndex` all verified against source. Zero new external dependencies; the whole phase is one script + one test file.
**Scope:** HOW to implement. WHAT is locked in `09-CONTEXT.md` (D-00a..f, D-01, D-02) and ROADMAP Phase 9 — do not re-litigate the sentinel-prefix contract, the one-retry budget, refusal-abort parity, or the additive-diff constraint.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Carried forward (locked by ROADMAP + Phase 8 — not re-decided):**
- **D-00a:** mp4 menus only — gif never shows the row (palette output ignores `-b:v`); pictures never see the quality menu at all
- **D-00b:** `target:<bytes>` (or equivalent sentinel) prefix through `select_quality`'s return, branched before the tier whitelist — the sentinel label can never reach the tier `case` or ffmpeg; strip-at-first-tab re-validation stays the single chokepoint
- **D-00c:** `omarchy-menu-input "Target size (e.g. 25M)"` is the prompt surface — already shipped; `[[ -s $selection_file ]]` semantics: non-empty → print + exit 0, else exit 1
- **D-00d:** Re-prompt once on empty submit or unparseable input, then cancel cleanly; Esc exits before the start notification like every sibling prompt
- **D-00e:** `omarchy-menu-input` must be stubbed in the harness (`FAKE_INPUT` knob + call-log line) in the same commit — the suite cannot hang on the real binary's `done_file` spin-wait
- **D-00f:** Interactive Custom-size run produces ffmpeg argv byte-identical to the equivalent `--target` invocation — one code path behind both entry points
- **D-01:** A *parseable but too-small* input aborts exactly like the CLI — planner refusal is terminal, the error surfaces with the achievable minimum, the menu ends. The re-prompt budget is for typos, not for retrying past a refusal.
- **D-02:** The second prompt carries an error hint (e.g. `Invalid size — e.g. 25M`) rather than re-showing the identical prompt.

### the agent's Discretion
- Exact sentinel label/subtext text (`Custom size…` + short subtext per the uniform-row-height requirement)
- Re-prompt loop shape (bounded counter vs. boolean flag) — must terminate after exactly one retry
- Where the sentinel branch sits in `select_quality`'s return handling — as long as it's before the tier whitelist and preserves D-00b
- Test row naming/fixtures for the `FAKE_INPUT` stub

### Deferred Ideas (OUT OF SCOPE)
- **Re-prompt on planner refusal with floor plumbed into the prompt** — explicitly rejected for this phase
- **Prefilled/remembered last custom size** — `omarchy-menu-input` has no initial-value arg today
- **Custom size row in gif menu** — deliberately absent per D-00a
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MENU-02 | mp4 quality menu gains `Custom size…` row → `omarchy-menu-input` → same parser/target path; empty/unparseable re-prompts once then cancels; empty submit is exit-0-with-empty, not a cancel | §2 verifies the exit-0-empty vs exit-1 distinction in `Menu.qml`/`omarchy-menu-input`; §3 gives the sentinel contract and both branch sites; §4 the bounded re-prompt loop; §5 the stub + assertion rows |
</phase_requirements>

---

## 1. Exact edit surface in `bin/omarchy-transcode`

File anatomy at HEAD `7847d99e` (645 lines — Phase 8 grew the 431-line base the milestone research cites): `select_quality` `:248-288`; the Phase-8 helper block `parse_target_size` `:308-324`, `plan_target` `:337-385`, `transcode_video_target` `:398-466`; `main` `:468-643` with the quality-menu gate `:602-604`, planner block `:610-614`, `output_path` `:616`, dispatch `:618-633`.

Three colocated hunks plus one new helper. `transcode_video*`, `output_path`, `plan_target`, `parse_target_size`, the dispatch tail, and `select_quality`'s *tier* path all stay byte-identical (additive-diff rules, `research/ARCHITECTURE.md` §Additive-Diff — v1.1's PR is still the conflict window).

### 1a. `select_quality` `:248-288` — append the sentinel row (between `:275` and `:277`)

Current tail of the row builder, verbatim [VERIFIED: bin/omarchy-transcode:261-277]:

```bash
  local kbps
  for tier in high medium low; do
    kbps=$(quality_kbps "$resolution" "$tier")
    ...
    rows+=($'\t'"$tier"$'\t'"$subtext")
  done

  selection=$(omarchy-menu-select "Select quality" "${rows[@]}" -- --default-index 1) || return
```

Insert between the loop's `done` and the `selection=` line, gated on format:

```bash
  # mp4 only: the sentinel row's label doubles as its key -- the menu returns
  # "label\tsubtext", and the strip below hands the label back verbatim.
  [[ $format == "mp4" ]] && rows+=($'\t'"$custom_label"$'\t'"$custom_subtext")
```

- **`$format` is already in scope** — `select_quality` takes `(input, format, resolution)` at `:249` and already branches on it at `:253`/`:263`. No signature change.
- **Append LAST, never insert** — `--default-index 1` pre-highlights row index 1 = `medium`. `MenuModel.dmenuDefaultIndex` [VERIFIED: shell/plugins/menu/MenuModel.js:497-503] clamps `index >= count → count-1`; at 4 rows index 1 still lands on medium. Inserting the sentinel before/inside the tier list would shift the highlight onto the wrong row.
- **Subtext is mandatory** — `rowHeightForDetail` [VERIFIED: Menu.qml:147-148] gives dmenu rows with detail `detailRowHeight`; all three tier rows always carry a subtext (`:265-273`, estimate or qualitative fallback), so a subtext-less sentinel row would render shorter. Recommend `"Enter a size like 25M"` (PITFALLS §8 suggestion); exact wording is agent discretion.
- **Single-source the label** — declare `local custom_label="Custom size…"` up in the `:250` locals line (add the two new vars there) so the row text and the match at §1b can't drift. The `…` is one U+2026 char, not three dots — the `[[ == ]]` match is byte-exact.

### 1b. `select_quality` — the sentinel branch (between `:279` and `:280`)

The chokepoint, verbatim [VERIFIED: bin/omarchy-transcode:279-287]:

```bash
  selection="${selection%%$'\t'*}"
  case "$selection" in
  high | medium | low) ;;
  *)
    echo "Invalid video quality: $selection (expected high, medium, or low)" >&2
    return 1
    ;;
  esac
  printf '%s' "$selection"
```

Branch immediately after the strip, before the `case` (D-00b — "extend the chokepoint, don't bypass it", ARCHITECTURE.md):

```bash
  selection="${selection%%$'\t'*}"

  if [[ $selection == "$custom_label" ]]; then
    bytes=$(prompt_target_size) || return   # Esc or exhausted re-prompt: cancel like every sibling
    printf 'target:%s' "$bytes"
    return
  fi

  case "$selection" in
  ...
```

- The `target:<bytes>` return **never re-enters** the whitelist — it is minted after the branch and printed straight to the return channel. The whitelist keeps rejecting every other foreign label (the `bogus\tjunk` pin at `test:607-617` keeps passing untouched).
- `bytes` is a guaranteed integer — `prompt_target_size` only returns 0 with `parse_target_size` output, so `target:%s` carries `^[0-9]+$` by construction.
- Esc on the *select* menu is unchanged: `omarchy-menu-select` exit 1 → `|| return` at `:277` → `select_quality` returns 1 → `quality=$(…)` fails → `main` dies under `set -e`, pre-notification. Esc on the *input* prompt rides the same `|| return` one frame down.

### 1c. New helper `prompt_target_size` — helper block, right after `parse_target_size` (`:324`)

Placement rationale: it is the menu-side wrapper around `parse_target_size`; putting it adjacent keeps the two parser consumers visually paired, and the helper block is where Phase-8 rules say new functions live (contiguous, never interleaved with v1.1 code). Calling a function defined later in the file is fine — definitions all load before `main "$@"` runs.

```bash
# Prompts for a free-text target size behind the Custom size… row. Re-prompts
# exactly once -- the second prompt carries an error hint so it reads as
# "invalid", not "didn't take" (D-02) -- then cancels. Esc cancels at either
# prompt like every sibling. Empty submits ride through parse_target_size with
# everything else: one validator for both entry points. Planner refusals are
# NOT this loop's business (D-01).
prompt_target_size() {
  local prompt="Target size (e.g. 25M)" answer bytes attempt
  for attempt in 1 2; do
    answer=$(omarchy-menu-input "$prompt") || return 1
    if bytes=$(parse_target_size "$answer"); then
      printf '%s' "$bytes"
      return 0
    fi
    prompt="Invalid size — e.g. 25M"
  done
  return 1
}
```

- `for attempt in 1 2` bounds the budget at exactly two prompts — first failure re-prompts once, second failure falls through to `return 1` (cancel). Equivalent boolean-flag shape is equally acceptable (discretion); do NOT use an unbounded `while :` with an inner counter — the loop bound must be visible in the construct.
- `answer=$(omarchy-menu-input "$prompt") || return 1` — exit 1 is Esc (§2) and cancels; exit 0 with empty `answer` is an empty submit and flows into `parse_target_size`, which rejects `""` via its regex with `Invalid target size: ` on stderr and returns 1 → re-prompt. One code path for empty AND garbage.
- `bytes=$(parse_target_size …)` inside `if` — the `if` condition both exempts the failure from `set -e` and preserves the status for the branch; parse errors print to stderr before the reprompt. Never `local bytes=$(…)` (masks status — Phase-8 Pitfall-4 convention).
- Alternative (equally valid): an explicit `[[ -z $answer ]] && { prompt=…; continue; }` before the parse if the planner prefers not to spend a stderr line on empty input — cosmetic difference only; stderr is invisible in the menu-launched flow anyway.
- Prompt strings per D-00c/D-02: `"Target size (e.g. 25M)"` first, `"Invalid size — e.g. 25M"` on retry. A single `prompt` variable mutated between iterations is the whole D-02 cost.
- `--width` is optional (`omarchy-menu-input:20-27` accepts it); matching the select menu's default 300 needs no flag. Discretion.

### 1d. `main()` — unwrap `target:<bytes>` inside the existing menu gate (`:602-604`)

Current gate, verbatim [VERIFIED: bin/omarchy-transcode:602-604]:

```bash
  if [[ $type == "video" && -z $quality && -z $target_bytes ]]; then
    quality=$(select_quality "$input" "$format" "$resolution")
  fi
```

This is THE minimal main-side change — the sentinel unwrap lives inside the gate so a CLI `--target` run (which skips the menu entirely, `-z $target_bytes` fails) can never see a `target:` value it didn't produce:

```bash
  if [[ $type == "video" && -z $quality && -z $target_bytes ]]; then
    quality=$(select_quality "$input" "$format" "$resolution")
    # A Custom size… pick returns target:<bytes> -- unwrap into the same two
    # variables --target sets, so the planner block, output_path, and the
    # dispatch below are byte-identical to a CLI run (D-00f).
    if [[ $quality == target:* ]]; then
      target_bytes="${quality#target:}"
      target_token=$(numfmt --to=iec "$target_bytes")
      quality=""
    fi
  fi
```

- **`quality=""` is load-bearing.** Without it, `target:26214400` flows into `output_path`'s 4th arg at `:616` (`${target_token:-$quality}` → a `stem-1080p-target:26214400.mp4` filename) and into `transcode_video`'s quality case at `:632` (`Invalid video quality: target:26214400`). Clearing it makes the downstream code see exactly what a `--target` run sees.
- After the unwrap, `target_bytes` set → planner block `:610-614` runs `plan_target` → `read -r resolution video_kbps` → `output_path` gets `target_token` → dispatch `:619` takes the `transcode_video_target` branch with the `-p` toast. Zero additional `main` edits.
- Defense-in-depth option (discretion): `[[ $target_bytes =~ ^[0-9]+$ ]] || { echo … >&2; return 1; }` after the `${quality#target:}` strip. Not strictly needed — the prefix is minted from `parse_target_size` output — but it makes the contract explicit at the trust boundary for ~1 line.

### 1e. Verified-untouched components

| Component | Why no change |
|-----------|---------------|
| `bin/omarchy-menu-input` | Already shipped; contract reused as-is (§2) |
| `bin/omarchy-menu-select` | `mode:"select"` payload `:87-110`, `--` arg parsing `:32-70`, `selectionFile` handshake `:81-84`/`:112-119` — the sentinel row is ordinary argv to it |
| `shell/plugins/menu/Menu.qml`, `MenuModel.js` | Input mode fully shipped (§2); `dmenuDefaultIndex` already clamps (§1a) |
| `transcode_video`, `transcode_video_target`, `plan_target`, `parse_target_size`, `output_path`, `output_size_label` | Phase-8 contract reused verbatim — that's the D-00f point |
| `usage()`/`# omarchy:args=`/`# omarchy:examples=` (`:6-7`, `:11-33`) | No new CLI surface — the row is menu-only. `test/cli` metadata pins keep passing unchanged (verify, don't edit) |
| `docs/menu.md`, `manual/` | Input mode documented at `docs/menu.md:156-173`; Phase 8 set the precedent of not touching `manual/` (additive-diff) |
| `default/nautilus-python/extensions/transcode.py` | Invokes bare `omarchy-transcode <path>` — the row reaches it through the existing interactive path for free |

---

## 2. `omarchy-menu-input` semantics — the three states, verified

The roadmap's "exit-0-with-empty is distinguishable from cancel" assumption is **verified true** — the two paths differ in what `Menu.qml` writes, not just in exit code:

`finishRequest` [VERIFIED: shell/plugins/menu/Menu.qml:118-136]:

```js
    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
```

And `omarchy-menu-input`'s tail [VERIFIED: bin/omarchy-menu-input:50-57]:

```bash
while [[ ! -e $done_file ]]; do
  sleep 0.05
done

if [[ -s $selection_file ]]; then
  cat "$selection_file"
else
  exit 1
fi
```

| User action | QML path | selectionFile | `-s` test | Binary result | Caller sees |
|-------------|----------|---------------|-----------|---------------|-------------|
| Esc (empty filter) | `cancel()` `:834` → `finishRequest(null)` `:835` → only `: > doneFile` `:131` | empty (untouched) | false | exit 1, no stdout | `$(…)` fails → `|| return` |
| Esc (text present) | `:1136-1139` — first Esc runs `setFilter("")`, menu stays open; second Esc cancels | — | — | (still open until second Esc) | two-stage Esc, harmless |
| Enter/Right on empty | `applyDmenuSelection("")` `:766`/`:1160` → `finishRequest("")` → `printf '%s\n' ""` writes `\n` | 1 byte (`\n`) | **true** | `cat` prints `\n`, **exit 0** | `answer=""`, status 0 |
| Enter/Right on text | same path with `filterText` verbatim `:765-766`, `:1158-1160` | `<text>\n` | true | `cat` prints text, exit 0 | `answer=<text>`, status 0 |

So the caller-side truth table is exactly what D-00d needs: **exit code distinguishes cancel (1) from submit (0); the captured string distinguishes empty from valid.** Empty submit is NOT an Esc — it must re-prompt, not abort. This is the single most important semantic the implementation must honor, and it falls out of `answer=$(…) || return` (Esc) vs. `parse_target_size "$answer"` (submit) naturally.

Other input-mode quirks the caller inherits (all verified, all already absorbed by the design): prompt is the placeholder (`:1210` dims `dmenuPrompt + "…"`); `filterText` starts `""` (`:877`) — no prefill; no validation/`maxLength` — all validation is bash-side; `rebuildDmenuDisplay` early-returns for input mode (`:558-561`) so the card renders header-only (`:115`); right-arrow submits identically to Enter (`:1158-1160`). No caller of `omarchy-menu-input` exists in `bin/` or `test/` today — this phase is its first consumer [VERIFIED: repo-wide grep, only `bin/omarchy-menu-input` itself and `docs/menu.md` match].

---

## 3. The `target:<bytes>` contract end-to-end — how it survives the chokepoint

**Row → return:** the sentinel row `$'\t'"Custom size…"$'\t'"<subtext>"` parses in `rebuildDmenuDisplay` as `["", "Custom size…", "<subtext>"]` → icon `""`, label `Custom size…`, detail `<subtext>` [VERIFIED: Menu.qml:569-572 — `parts.shift()` for icon, `parts.shift()` for label, `parts.join("\t")` for detail]. On pick, `:771` returns `picked.label + "\t" + picked.detail` = `Custom size…\t<subtext>` — matching `omarchy-menu-select`'s documented contract [VERIFIED: bin/omarchy-menu-select:9-13: "an option with a subtext returns `<label><TAB><subtext>`, so callers with same-named rows get the subtext back as the stable key"].

**Return → strip → branch:** `:279` `selection="${selection%%$'\t'*}"` yields `Custom size…`; the §1b `if` matches it against the single-sourced `$custom_label` before the tier `case` runs. The whitelist never sees the sentinel — D-00b satisfied — and every other foreign label still dies at `*)`.

**Branch → return channel:** on a successful prompt, `printf 'target:%s' "$bytes"` writes the ONLY thing on `select_quality`'s stdout — `main` captures it into `quality` at `:603`. The `target:` prefix cannot collide with the tier vocabulary (`high|medium|low`) and cannot be minted by the menu (the label match is exact, the bytes come only from `parse_target_size`'s integer output).

**Return → unwrap → Phase-8 machinery:** §1d's `[[ $quality == target:* ]]` unwrap sets `target_bytes`/`target_token` and clears `quality`; from `:610` down the code path is literally the `--target` path — `plan_target` → `read` → `output_path ${target_token:-…}` → `-p` start toast → `transcode_video_target` → shared copy/size/done tail. D-00f's "byte-identical argv" holds by construction: the only difference between the two entry points is which side of `:603` filled `target_bytes`.

**Alternative considered and rejected:** return `target:<raw-typed-text>` and parse in `main`. It splits the menu round-trip across functions, puts the re-prompt loop outside the menu flow (a second summon could only happen after `select_quality` returned — wrong shape), and leaks unvalidated text one boundary further. The chosen shape keeps all menu plumbing inside the menu helper.

---

## 4. Re-prompt loop — where the budget lives

The retry budget lives **entirely inside `prompt_target_size`** (§1c). Neither `select_quality` nor `main` knows re-prompting happened — they see one return value (`target:<bytes>`) or one status (1 = cancel). This is what makes the loop cancel-clean: every exit path from the helper is either "bytes on stdout" or "return 1", and `return 1` propagates through `select_quality`'s `|| return` and `quality=$(…)` into `main`'s `set -e` abort — the identical chain Esc on the select menu already uses.

Termination proof for `for attempt in 1 2`: iteration 1 (initial prompt) — Esc → `return 1`; valid → `return 0`; empty/invalid → set hint prompt, continue. Iteration 2 (hinted re-prompt) — Esc → `return 1`; valid → `return 0`; empty/invalid → loop ends → `return 1`. Exactly two `omarchy-menu-input` invocations maximum, exactly one re-prompt, and no path loops.

**Boundary that must not blur (D-01):** the loop wraps `parse_target_size` ONLY. A parseable-but-too-small size returns bytes successfully → `target:<bytes>` → `plan_target` refuses below the floor → `plan=$(plan_target …)` at `:612` fails → `set -e` aborts `main` with the refusal on stderr, before the start toast — byte-for-byte the CLI posture. Do NOT wrap the planner in the retry loop; a refusal is a verdict, not a typo.

---

## 5. Test harness — `omarchy-menu-input` stub + case rows

Extend `test/shell.d/transcode-quality-test.sh` in the same commit (D-00e / Pitfall 11 — the unstubbed real binary spins forever at `omarchy-menu-input:50-52` waiting on `done_file`).

### 5a. The stub — three states, no RC knob needed

The real binary has exactly three outcomes: submit-text (exit 0 + text), submit-empty (exit 0 + empty), Esc (exit 1 + empty). There is no fourth state to control — a summon failure dies nonzero identically to Esc — so a per-invocation answer variable is the whole API:

```bash
# omarchy-menu-input mirrors the real binary's three states: set FAKE_INPUT
# prints it and exits 0 (submit); set-but-empty FAKE_INPUT exits 0 with empty
# stdout (empty submit -- NOT a cancel); unset exits 1 (Esc, and the tripwire
# for runs that must never reach the input prompt). Per-invocation knobs
# (FAKE_INPUT, FAKE_INPUT2, …) feed the re-prompt loop -- same convention as
# FAKE_OUT_BYTES/FAKE_OUT_BYTES2, with the invocation number counted off the
# just-logged menu-input: line exactly like the pass-2 counter at :79.
cat >"$STUB_DIR/omarchy-menu-input" <<'SH'
#!/bin/bash
printf 'menu-input: %s\n' "$*" >>"$CALLS"
n=$(grep -c '^menu-input:' "$CALLS")
var=FAKE_INPUT
(( n > 1 )) && var="FAKE_INPUT$n"
[[ -z ${!var+x} ]] && exit 1
printf '%s' "${!var}"
SH
```

- **Why unset = Esc = tripwire:** the `menu-input:` line is logged *before* the decision, so an unexpected call still leaves evidence in `$calls` and exits 1 — same dual-purpose shape as the `omarchy-menu-select` stub (`:136-144`, unset `FAKE_PICK` → exit 1).
- **`FAKE_INPUT2` unset on a second call** exits 1 — reads naturally as "user Esc'd the re-prompt", which is the desired default for single-answer tests.
- **`$*` logs argv unquoted** (matching the menu-select stub's `printf 'menu-select: %s\n' "$*"` at `:138`) — the recorded prompt text greps literally, e.g. `grep -F 'menu-input: Target size (e.g. 25M)'`. NOTE the asymmetry: only the ffmpeg/magick stub uses `%q` (`:38-39`); menu stubs log raw — so `grep -F $'\tCustom size…'` against `menu-select:` lines matches real tabs (verified: `%q` would emit `$'\t…'` escapes and NOT match a literal-tab pattern — confirmed live on this system).
- `run_transcode` needs **no changes** — `HOME`/`PATH`/`CALLS`/`TMPDIR` already export at `:184`, and `VAR=x run_transcode` env prefixes reach the stubs.
- chmod: the new stub lands inside the existing `chmod +x "$STUB_DIR"/*` at `:173`.

### 5b. Call-log levels per scenario (pin these precisely — "cancel cleanly" is NOT an empty log)

| Scenario | `menu-select:` | `menu-input:` | `ffprobe:` | `notification:`/`ffmpeg` | Exit |
|----------|---------------|---------------|------------|--------------------------|------|
| Happy Custom path (`25M`) | 1 (4 rows incl. sentinel) | 1 | **4** (2 estimate probes `select_quality:253-258` + 2 planner probes `plan_target:350-352`) | `-p` start + `-r` + done + 2 ffmpeg | 0 |
| Esc on input prompt | 1 | 1 | 2 | none | 1 |
| Empty submit → valid | 1 | 2 (2nd line carries the hint) | 4 | full set | 0 |
| `bogus` → valid | 1 | 2 | 4 | full set | 0 |
| `bogus` → `bogus` (budget out) | 1 | 2 | 2 (planner never reached) | none | 1 |
| `bogus` → Esc | 1 | 2 | 2 | none | 1 |
| `1M` (parseable, below floor) | 1 | 1 | 4 | none — D-01 refusal | 1 |
| gif menu | 1 (3 rows, no sentinel) | 0 | 0 | gif encode set | 0 |

The `ffprobe: 4` count on happy paths is the trap to pin correctly — the mp4 menu probes for estimate subtexts *before* the pick, then `plan_target` probes again. A pin copied from the CLI's "exactly 2" row (`:779`) would be wrong here.

### 5c. New case rows

| Row | Invocation + knobs | Assert |
|-----|--------------------|--------|
| Row present | `FAKE_DURATION=60 FAKE_PICK=$'medium\t…' in.mov mp4 1080p` | `menu-select:` line `grep -F $'\tCustom size…\t'` (subtext text per chosen wording); `--default-index 1` still logged |
| gif absent | `FAKE_PICK=$'low\t5 fps' in.mov gif 720p` | `! grep -F 'Custom' "$calls"`; run encodes gif normally |
| Interactive ≡ CLI argv | `FAKE_PICK=$'Custom size…\t<subtext>' FAKE_INPUT=25M FAKE_DURATION=60` | `grep '^ffmpeg '` lines `cmp`-identical to the `--target 25M` run's; `out=in-1080p-25M.mp4`; `menu-input: Target size (e.g. 25M)` logged; `-b:v 3233k` on pass 2 |
| Notification parity | same run | `notification:` lines `cmp`-identical to the `--target` run's (`-p`, `pass 1/2`, `-r 7 pass 2/2`, done) — the strongest one-code-path pin |
| Empty → valid | `FAKE_INPUT="" FAKE_INPUT2=25M` | 2 `menu-input:` lines; 2nd `grep -F 'Invalid size'`; run completes |
| Bogus → valid | `FAKE_INPUT=bogus FAKE_INPUT2=25M` | 2 `menu-input:` lines; stderr got `Invalid target size: bogus`; run completes |
| Bogus → bogus | `FAKE_INPUT=bogus FAKE_INPUT2=bogus` | exit nonzero; 2 `menu-input:` lines; no `notification:`/`ffmpeg` |
| Esc on prompt | `FAKE_PICK=Custom…`, `FAKE_INPUT` unset | exit nonzero; 1 `menu-input:` line; no `notification:`/`ffmpeg` (pre-notification abort like siblings) |
| Esc on re-prompt | `FAKE_INPUT=bogus`, `FAKE_INPUT2` unset | exit nonzero; 2 `menu-input:` lines |
| Floor refusal parity (D-01) | `FAKE_INPUT=4M FAKE_DURATION=60` | exit 1; stderr `smallest achievable` + `4 MB`; no `notification:`/`ffmpeg` |
| Probe failure parity | `FAKE_INPUT=25M`, `FAKE_DURATION` unset | exit 1; `Cannot determine duration` (menu probes already failed → qualitative subtexts; planner refuses) |
| Sentinel never reaches tier case | happy-path run | `! grep -F 'Invalid video quality' stderr`; no ffmpeg/`out=` line ever contains `Custom` or `target:` |
| Foreign label still dies | existing `bogus\tjunk` pin `:607` | unchanged — keeps passing |
| IN-01 closure | `run_transcode … --target ""` | add `""` to the `:872` reject loop inputs |

Constraint on test invocations: keep 3 positionals (`in.mov mp4 1080p`) so only the quality menu fires — `FAKE_PICK` is single-valued per run and must answer the ONE menu-select call with the sentinel pick (the menu-picked-gif pin `:916` exploits the same single-answer convention).

---

## 6. Phase-specific pitfalls

1. **Sentinel reaching the tier `case` (PITFALLS §8).** If the `if [[ $selection == "$custom_label" ]]` branch is missing/misplaced, the pick dies `Invalid video quality: Custom size…`; if instead the label were added to the whitelist, `target:` text would leak toward `transcode_video`/`output_path`. Branch after the `:279` strip, before the `:280` case; single-source the label. *Warning sign:* stderr `Invalid video quality: Custom size…` on a sentinel pick.
2. **Empty submit treated as cancel.** `omarchy-menu-input` exits **0** on empty submit (writes `\n` — §2). `[[ -z $answer ]] && return 1` or treating `||` failure as the only cancel path inverts SC-3. The exit code is the cancel signal; the string emptiness is the empty-submit signal.
3. **Re-prompt wrapping `plan_target`.** The budget covers parse failures only (D-01). A floor refusal must abort via the planner's own `return 1` → `set -e` — never re-summon the input.
4. **Row appended unconditionally → gif gets it.** `select_quality` serves gif too (`:602` gate is format-blind; gif rows exist at `:263-264`). Gate the append `[[ $format == "mp4" ]]` (D-00a). *Warning sign:* `Custom` in a gif run's `menu-select:` line.
5. **Row inserted before/among tiers.** `--default-index 1` is positional — a sentinel at index ≤1 steals medium's pre-highlight (MenuModel.js:497-503 clamps, doesn't reorder). Append after the loop.
6. **Subtext-less row → uneven heights.** `rowHeightForDetail` gives detail-rows a taller card row (Menu.qml:147-148); all tier rows always carry subtexts. Sentinel without subtext renders visibly shorter — the exact "looks broken" v1.1 fixed.
7. **Unstubbed `omarchy-menu-input` in the harness (PITFALLS §11 — FATAL).** The real binary spin-waits on `done_file` forever (`:50-52`); the suite hangs, never fails. Stub ships in the same commit.
8. **`local x=$(…)` masking.** `local bytes=$(parse_target_size …)` always returns 0 — re-prompt never triggers, garbage flows. Captures on their own lines or inside `if` conditions.
9. **`quality` left holding `target:<bytes>`.** Forget `quality=""` in the §1d unwrap → `output_path` bakes `target:26214400` into the filename and `transcode_video` rejects it as a quality. The parity test (`cmp` vs the `--target` run's argv) catches this instantly.
10. **Stray stdout inside `select_quality`.** It runs in `$(…)` — anything but the final `printf` corrupts `quality`. `omarchy-menu-input`'s stdout must be captured into `answer`, never leaked; debug `echo`s are fatal.
11. **Copying the CLI's "exactly 2 ffprobe" pin.** Interactive Custom path probes 4× (§5b) — pin the right count or the test false-reds.
12. **Ellipsis drift.** `…` is one U+2026 char; `Custom size...` (three dots) never matches the label and dies at `*)`. Single-sourcing via `$custom_label` makes drift impossible.

---

## 7. Deferred-item closures (natural to this commit)

- **IN-01** (`deferred-items.md:7`): add `""` to the `--target` reject-loop inputs at `test:872` — one token in the `for bad in` list, exits 2 with `Invalid target size: ` on stderr. Closes the unpinned contract the menu path now shares.
- **IN-03** (`deferred-items.md:9`): `plan_target`'s first floor `case` (`:364-368`) lacks `*)` — an out-of-vocabulary `res` leaves `floor` empty, `(( video_kbps >= floor ))` reads it as 0, and a bogus rung could print to `main`'s `read`. The Phase-9 caller still passes the `:578-584`-validated `resolution`, so it stays unreachable — but the helpers are now genuinely multi-caller; add `*) echo "Invalid video resolution: $res" >&2; return 1 ;;` while the file is open. One line, closes the finding.
- IN-02/IN-04/IN-05/IN-06: not touched by this phase's edit sites — leave deferred.

---

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Free-text prompt UI | A new prompt mode, QML changes, or flags on `omarchy-menu-select` | `omarchy-menu-input` (shipped) | `mode:"input"` is wired end-to-end; zero QML per phase boundary |
| Size validation | A menu-side regex or a second parser | `parse_target_size` verbatim | One validator behind both entry points is the D-00f/IN-01 contract |
| Cancel/Esc semantics | Custom exit-code scheme | `omarchy-menu-input`'s `[[ -s $selection_file ]]` → exit 0/1 | Matches every sibling prompt's contract; harness already models it via `FAKE_PICK` |
| Re-prompt loop | Recursion into `select_quality`, or re-summon from `main` | Bounded `for`/`while` inside `prompt_target_size` | Keeps the return contract single-valued; terminates visibly |

## Environment Availability

| Dependency | Required by | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `omarchy-menu-input` | Custom-row prompt | ✓ shipped (`bin/`, 58 lines) | — | — |
| `omarchy-menu-select` | Quality menu | ✓ shipped | — | — |
| `Menu.qml` input mode | Input card | ✓ shipped (`:866`, `:765-766`) | — | — |
| `numfmt`, `ffprobe`, `ffmpeg` | Parser/planner/encoder | ✓ harnessed since Phase 8 | coreutils/ffprobe stubs | — |
| bash ≥5 (`${!var}` indirection for stub knobs) | test stub | ✓ (shebang `#!/bin/bash`; `${normalized^^}` already used at `:315`) | — | — |

No missing dependencies; no packages installed — Package Legitimacy Audit is N/A this phase.

## Security Domain

Only ASVS V5 (Input Validation) applies — free text enters via `filterText` verbatim (Menu.qml:766). Mitigations are the shipped contract reused: regex-gate + `numfmt` inside `parse_target_size` (`:311-321`); only integer bytes cross into `target:<bytes>`; the filename token comes from `numfmt --to=iec`, never raw text; no `eval`, no string-built commands; `awk -v` only for math. No new threat surface beyond the already-reviewed Phase-8 parser (see `08-SECURITY.md`); the sentinel label is a fixed constant, not user data.

## Validation Architecture

Nyquist gate — every Phase-9 success criterion maps to stub-harness assertions; the whole phase is automatable. Commands: `bash test/shell.d/transcode-quality-test.sh` (focused), `./test/cli` (metadata lint — unchanged but run anyway), `bash -n bin/omarchy-transcode` (syntax), `./test/shell` (full suite — **7 pre-existing environmental failures** per STATE.md: bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths; do not chase them).

| # | Success criterion | Automated proof |
|---|-------------------|------------------|
| 1 | mp4 menu shows `Custom size…` 4th w/ subtext; gif never | §5c "Row present": `grep -F $'\tCustom size…\t<subtext>'` on the `menu-select:` line + `--default-index 1` retained; "gif absent": `! grep -F 'Custom' "$calls"` on a gif run |
| 2 | Row → `omarchy-menu-input "Target size (e.g. 25M)"`; valid answer ≡ `--target` argv | §5c "Interactive ≡ CLI argv": `cmp` the `^ffmpeg` lines (and `notification:` lines) between the Custom-pick run and the `--target 25M` run; `menu-input: Target size (e.g. 25M)` logged |
| 3 | Empty submit + unparseable each re-prompt once then cancel; Esc pre-notification | §5c rows: `FAKE_INPUT="" FAKE_INPUT2=25M` and `bogus`→`25M` (2 `menu-input:` lines, 2nd carries `Invalid size`, run completes); `bogus`→`bogus` and Esc rows (exit nonzero, no `notification:`/`ffmpeg`) |
| 4 | Sentinel never reaches tier case/ffmpeg; strip stays the chokepoint | Happy-path run greps `! 'Invalid video quality'` on stderr; no recorded `ffmpeg`/`out=` line contains `Custom`/`target:`; the existing `bogus\tjunk` foreign-label pin (`:607-617`) unchanged |
| 5 | `omarchy-menu-input` stubbed same commit (no hang) | The suite going green IS the proof — every Custom-row row above exercises the stub; an unstubbed binary hangs `test:50-52`, so green means stubbed |

**Requirement traceability:** MENU-02 ← SC 1–5 (all five criteria are facets of it).

**Per-task validation:**

| Likely task | Automated check | Manual check |
|-------------|-----------------|--------------|
| 09-01 (single atomic commit: sentinel row + prompt helper + `target:` unwrap + stub + rows) | `bash -n bin/omarchy-transcode`; `bash test/shell.d/transcode-quality-test.sh` green (82 → ~92 pins); `./test/cli` exit 0; `git diff` review confirms tier path byte-identical | Optional dogfood in the running UI: `omarchy transcode <clip> mp4 1080p` → pick `Custom size…` → type `25M` → verify the input card renders (prompt-as-placeholder), Enter submits, Esc cancels, a garbage entry re-prompts with the hint. Non-blocking — QML is untouched; stubs prove the contract. |

**Wave 0 gaps:** none — existing infrastructure covers everything; the `omarchy-menu-input` stub lands inside the same atomic commit as the feature (Pitfall 11 forbids a follow-up).

**Known limitations to carry into the plan:**

- `select_quality`'s mp4 estimate probes run even when the user then picks Custom — 2 extra `ffprobe` calls versus the CLI path (§5b). Inherent to showing tier estimates beside the sentinel row; milliseconds locally; not a bug to fix.
- `prompt_target_size`'s stderr on menu-launched runs is invisible (no terminal) — the D-02 hint prompt is the real error surface; stderr text exists for terminal callers only.
- The sentinel label match is exact — renaming the row later means touching the one `$custom_label` constant (single-sourced for exactly this reason).
- Esc-on-input is two-stage when text is present (QML clears the filter first) — inherited UX, consistent with every other filterable menu; documented, not changed.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Subtext text `Enter a size like 25M` and hint `Invalid size — e.g. 25M` — wording recommendations, not locked | §1a/§1c | Cosmetic — strings are pinned in tests either way |
| A2 | `prompt_target_size` as a named helper vs. inline in `select_quality` — recommendation within discretion | §1c | Structure only; contract identical |
| A3 | Stub knob shape (`FAKE_INPUT`/`FAKE_INPUT2`, unset=Esc) — within D-00e's discretion | §5a | Test-internal only |

## Open Questions

1. **None blocking.** All seven research questions resolved against source: the sentinel rides `label\tsubtext` → strip → pre-case branch → `target:<bytes>` → `main` unwrap (§1b/§1d, §3); exit-0-empty vs cancel is genuinely distinguishable (§2); row returns label+subtext, label survives the strip (§3); stub needs `FAKE_INPUT`/`FAKE_INPUT2` + call-log line, no RC knob (§5a); the budget lives in `prompt_target_size` (§4); pitfalls enumerated (§6); validation fully automated (Validation Architecture).

## Sources

### Primary (verified in-repo this session)
- `bin/omarchy-transcode` @ `7847d99e` — `select_quality` `:248-288` (row build `:274`, menu call `:277`, strip `:279`, whitelist `:280-286`), `parse_target_size` `:308-324`, `plan_target` `:337-385`, `transcode_video_target` `:398-466`, menu gate `:602-604`, planner `:610-614`, `output_path` `:616`, dispatch `:618-633`
- `bin/omarchy-menu-input` — full file; handshake `:32-57`, `[[ -s $selection_file ]]` `:54`, spin-wait `:50-52`
- `bin/omarchy-menu-select` — return contract header `:9-13`, `mode:"select"` payload `:87-110`
- `shell/plugins/menu/Menu.qml` — `finishRequest` `:118-136`, input submit `:765-766`/`:1158-1160`, Esc `:1136-1139`, `cancel` `:834-838`, input-mode routing `:866`/`:558-561`/`:115`/`:1210`, row parse `:569-572`, pick return `:771`, `rowHeightForDetail` `:147-148`
- `shell/plugins/menu/MenuModel.js:497-503` — `dmenuDefaultIndex` clamping
- `test/shell.d/transcode-quality-test.sh` — stubs `:34-171`, `run_transcode` `:180-189`, foreign-label pin `:607-617`, gif pins `:577-592`, `%q` vs `%s` logging asymmetry (verified live: `%q` emits `$'\t…'` escapes; menu stubs log raw tabs), suite green 82/82
- `.planning/phases/08-non-interactive-target-size-targeting/deferred-items.md` — IN-01/IN-03
- `.planning/research/{ARCHITECTURE,PITFALLS}.md` — sentinel contract, pitfalls 8/11

## Metadata

**Confidence breakdown:**
- Edit surface / contracts: HIGH — every site read at HEAD, quotes verbatim
- Input-mode semantics: HIGH — QML + binary both read; three-state table derived from `finishRequest` source
- Pitfalls: HIGH — all source-verified or live-tested (`%q` tab escaping, suite green run)

**Research date:** 2026-09-17
**Valid until:** next commit touching `select_quality`, `main`'s menu gate, or `omarchy-menu-input` — line numbers drift, contracts don't

---

*Phase 9 research — consolidates `.planning/research/{ARCHITECTURE,PITFALLS}.md` + `09-CONTEXT.md` against `bin/omarchy-transcode`, `bin/omarchy-menu-input`, `shell/plugins/menu/Menu.qml`, and `test/shell.d/transcode-quality-test.sh` at HEAD `7847d99e`.*
