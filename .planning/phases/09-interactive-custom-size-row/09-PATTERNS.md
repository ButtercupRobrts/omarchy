# Phase 9 Pattern Mapping: Interactive `Custom size…` row

**Mapped:** 2026-09-17 against `bin/omarchy-transcode` (645 lines) and `test/shell.d/transcode-quality-test.sh` (1216 lines) at HEAD — every cited range re-read this session; line numbers confirmed current.
**Files touched:** exactly two — `bin/omarchy-transcode` (modified, additive: 3 hunks + 1 helper) and `test/shell.d/transcode-quality-test.sh` (modified: 1 stub + ~10 case rows). No new files.

---

## 1. File inventory — roles and data flow

| File | Role | Data flow | Change class |
|------|------|-----------|--------------|
| `bin/omarchy-transcode` | Target script — the whole feature | menu pick `label\tsubtext` → strip-at-tab → sentinel-label match → `prompt_target_size` (≤2 `omarchy-menu-input` rounds → `parse_target_size` → integer bytes) → `printf 'target:%s'` → `main()` unwraps into `target_bytes`/`target_token`/`quality=""` → **byte-identical Phase-8 pipeline** (`plan_target` → `output_path` → `transcode_video_target`) | Modified: sentinel row append in `select_quality` (`:275`→`:277` slot), sentinel branch after the strip (`:279`→`:280` slot), new `prompt_target_size` helper adjacent to `parse_target_size` (after `:324`), `target:` unwrap inside the `:602-604` gate. All Phase-8 helpers, tier paths, and dispatch byte-identical. |
| `test/shell.d/transcode-quality-test.sh` | Stub harness — proves argv parity, re-prompt budget, Esc/cancel, gif absence | `FAKE_INPUT`/`FAKE_INPUT2` env knobs → `menu-input:` call-log lines → per-invocation counter off `grep -c '^menu-input:'` | Modified: one new stub (~10 lines, inside `chmod +x` sweep at `:173`) + case rows appended near the `--target` block. `run_transcode` (`:180-189`) needs zero changes. |

**Read-only references** (patterns copied from, never edited): `bin/omarchy-menu-input` (58 lines — `[[ -s $selection_file ]]` three-state contract), `bin/omarchy-menu-select` (`--default-index`, post-`--` args, `label\tsubtext` return contract `:9-15`), `bin/omarchy-launch-shell` + `test/shell.d/base-test.sh` (the `for attempt in 1 2 3` bounded-loop idiom), `bin/omarchy-menu-plugin`/`omarchy-menu-timezone` (menu-cancel `|| exit` conventions), `docs/menu.md:156-173` (select/input mode contract).

---

## 2. `bin/omarchy-transcode` — site-by-site analogs

### 2a. `select_quality` row construction (`:248-275`) — where the sentinel row appends

**Analog — the tier loop itself, verbatim:**

```bash
# bin/omarchy-transcode:260-275
  local kbps
  for tier in high medium low; do
    kbps=$(quality_kbps "$resolution" "$tier")
    if [[ $format == "gif" ]]; then
      subtext=$(quality_token gif "$resolution" "$tier")
    elif [[ -n $duration && -n $kbps ]]; then
      subtext="$(quality_token mp4 "$resolution" "$tier") · $(estimate_label "$duration" "$kbps" "$audio_kbps" "$src_bytes")"
    else
      case "$tier" in
      high) subtext="Best quality" ;;
      medium) subtext="Balanced" ;;
      low) subtext="Smallest file" ;;
      esac
    fi
    rows+=($'\t'"$tier"$'\t'"$subtext")
  done
```

**Pattern to copy:**

```bash
  [[ $format == "mp4" ]] && rows+=($'\t'"$custom_label"$'\t'"$custom_subtext")
```

- Insert **between `done` (`:275`) and `selection=` (`:277`)** — appended LAST. `--default-index 1` is positional; a sentinel at index ≤1 steals medium's pre-highlight (`MenuModel.dmenuDefaultIndex` clamps `index >= count → count-1`, never reorders).
- **mp4-gate is mandatory** — `select_quality` serves gif (`:263` branches on `$format`, already in scope at `:249`; no signature change). Ungated append puts the row in gif's menu (D-00a violation).
- **Subtext is mandatory** — every existing row carries one (`:265-273` — estimate or qualitative fallback); `rowHeightForDetail` (Menu.qml:147-148) renders subtext-less rows shorter. Uniform heights is a v1.1 fix.
- **Single-source the label** — add `local custom_label="Custom size…" custom_subtext="…"` to the existing locals line at `:250`. The `…` is one U+2026 char; the `[[ == ]]` match at §2b is byte-exact, so the row text and the match must share the variable or drift is inevitable (research Pitfall 12).

### 2b. The strip/validate chokepoint (`:279-287`) — where the sentinel branches

**Verbatim current code:**

```bash
# bin/omarchy-transcode:277-287
  selection=$(omarchy-menu-select "Select quality" "${rows[@]}" -- --default-index 1) || return

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

**Pattern to copy** — the branch slots between the strip (`:279`) and the `case` (`:280`), extending the chokepoint rather than bypassing it (D-00b):

```bash
  selection="${selection%%$'\t'*}"

  if [[ $selection == "$custom_label" ]]; then
    bytes=$(prompt_target_size) || return
    printf 'target:%s' "$bytes"
    return
  fi

  case "$selection" in
  ...
```

- The whitelist keeps rejecting every other foreign label — the existing `bogus\tjunk` pin (`test:607-617`) stays green untouched.
- `target:%s` carries `^[0-9]+$` by construction — `prompt_target_size` only returns 0 with `parse_target_size` output.
- `|| return` mirrors the `omarchy-menu-select` cancel chain at `:277` — Esc on the input prompt propagates exactly like Esc on the select menu (both die pre-notification under `set -e` via `quality=$(…)` at `:603`).

### 2c. Menu-cancel conventions in `bin/` — which `||` shape to use

`select_quality` is a function returning through `$(…)`, so its cancel is `|| return` (status propagates to `main`'s `set -e`). Top-level scripts use `|| exit`:

```bash
# bin/omarchy-menu-plugin:33-34 — cancel = clean exit 0 (nothing to do)
selection=$(omarchy-menu-select "${1^} plugin" <<<"$rows") || exit 0

# bin/omarchy-menu-timezone:9 — cancel = exit 1
timezone=$(timedatectl list-timezones | omarchy-menu-select "Set timezone" -- --width 520 --maxheight 520) || exit 1

# bin/omarchy-capture-screenrecording-with-webcam:15 — same || exit 1 shape
selection=$(omarchy-menu-select "Select Webcam" "${devices[@]}" -- --width 520 --maxheight 520) || exit 1
```

Inside `main()`, the sibling menus rely on bare `set -e` propagation with no `||` at all (`:515`, `:549-551`, `:557-559`).

**Pattern:** inside `prompt_target_size` use `answer=$(omarchy-menu-input "$prompt") || return 1`. Inside `select_quality` `bytes=$(prompt_target_size) || return`. **Never `local x=$(…)`** — masks the status (the Phase-8 Pitfall-4 convention already documented in `plan_target`'s comment at `:348-349`).

### 2d. `omarchy-menu-input` contract — the prompt surface (read-only analog)

No caller exists in `bin/` today — this phase is its first consumer. The whole contract is 58 lines:

```bash
# bin/omarchy-menu-input:11, :50-57
prompt="${1:-Input}"
...
while [[ ! -e $done_file ]]; do
  sleep 0.05
done

if [[ -s $selection_file ]]; then
  cat "$selection_file"
else
  exit 1
fi
```

**The three-state truth table** (verified against `Menu.qml:118-136` `finishRequest` in 09-RESEARCH §2):

| User action | selectionFile | Exit | Caller sees |
|-------------|---------------|------|-------------|
| Esc | empty | 1 | `$(…)` fails → `|| return` — **cancel** |
| Enter on empty | `\n` (1 byte, `-s` true) | **0**, prints empty | `answer=""`, status 0 — **empty submit, NOT cancel** |
| Enter on text | `<text>\n` | 0, prints text | `answer=<text>` — **valid path through parser** |

The exit code is the cancel signal; string emptiness is the empty-submit signal. Both empty and garbage flow into `parse_target_size` — one validator for both (D-00c/D-00d). Optional `--width` flag at `:20-27`; omitting it matches the select menu's default.

### 2e. `parse_target_size` / `plan_target` (`:308-324`, `:337-385`) — reused verbatim, the call-shape contract

```bash
# :308-324 — pure validator: integer bytes on stdout, error on stderr, return 1.
parse_target_size() {
  local raw="$1" normalized bytes
  [[ $raw =~ ^[0-9]+(\.[0-9]+)?([kKmMgG][bB]?)?$ ]] ||
    { echo "Invalid target size: $raw" >&2; return 1; }
  normalized="${raw%[bB]}"; normalized="${normalized^^}"
  [[ $normalized =~ [KMG]$ ]] || normalized+="M"
  bytes=$(numfmt --from=iec "$normalized") || { echo "Invalid target size: $raw" >&2; return 1; }
  (( bytes > 0 )) || { echo "Invalid target size: $raw" >&2; return 1; }
  printf '%s' "$bytes"
}
```

Call it inside an `if` condition — exempts failure from `set -e` AND preserves status for the branch:

```bash
if bytes=$(parse_target_size "$answer"); then
  printf '%s' "$bytes"; return 0
fi
```

`plan_target` keeps its existing call shape at `:610-614` — `plan=$(plan_target "$input" "$target_bytes" "$requested_resolution")` + `read -r resolution video_kbps <<<"$plan"`. **D-01 boundary:** the re-prompt loop wraps `parse_target_size` ONLY; a parseable-but-too-small size returns bytes → `target:<bytes>` → planner refusal → `set -e` abort — byte-for-byte the CLI posture. Never re-summon the input on a refusal.

### 2f. `main()` gate + `target:` unwrap (`:602-616`) — the sentinel landing site

```bash
# current :602-604
  if [[ $type == "video" && -z $quality && -z $target_bytes ]]; then
    quality=$(select_quality "$input" "$format" "$resolution")
  fi
```

**Pattern — unwrap inside the gate** so a CLI `--target` run (which skips the menu) can never see a `target:` value it didn't produce:

```bash
  if [[ $type == "video" && -z $quality && -z $target_bytes ]]; then
    quality=$(select_quality "$input" "$format" "$resolution")
    if [[ $quality == target:* ]]; then
      target_bytes="${quality#target:}"
      target_token=$(numfmt --to=iec "$target_bytes")
      quality=""
    fi
  fi
```

- `target_token=$(numfmt --to=iec …)` mirrors the `--target` flag arm verbatim (`:484-485`).
- **`quality=""` is load-bearing** — otherwise `target:26214400` flows into `output_path`'s 4th arg (`:616`) and `transcode_video`'s quality case (`:632`).
- After the unwrap, `:610-633` runs the Phase-8 path untouched — D-00f's byte-identical-argv holds by construction.

### 2g. Bounded retry-loop convention — the `for attempt in` idiom

The repo's bounded-retry idiom is a visible `for` bound, success `return 0`, exhaustion `return 1`:

```bash
# bin/omarchy-launch-shell:37-46 (and identically test/shell.d/base-test.sh:55-61)
compositor_alive() {
  local attempt
  for attempt in 1 2 3; do
    hyprctl -j monitors >/dev/null 2>&1 && return 0
    (( attempt < 3 )) && sleep 0.5
  done
  return 1
}
```

**Pattern for `prompt_target_size`** (new helper, placed right after `parse_target_size` at `:324` — Phase-8 helper-block convention: new functions live contiguous in the `:302-466` block, never interleaved with v1.1 code):

```bash
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

The bound is visible in the construct (`for attempt in 1 2`) — do NOT use `while :` + inner counter. The D-02 hint costs one reassigned `prompt` variable. `select_quality` and `main` never know a re-prompt happened — they see `target:<bytes>` or status 1.

---

## 3. `test/shell.d/transcode-quality-test.sh` — site-by-site analogs

### 3a. The `omarchy-menu-input` stub — mirrors the `omarchy-menu-select` stub (`:136-144`)

**Analog, verbatim:**

```bash
# :136-144 — dual-mode: unset FAKE_PICK = tripwire exit 1 (runs that must
# never go interactive), empty = Esc, set = answer. printf '%s' not '%s\n'
cat >"$STUB_DIR/omarchy-menu-select" <<'SH'
#!/bin/bash
printf 'menu-select: %s\n' "$*" >>"$CALLS"
if [[ -z ${FAKE_PICK+x} ]]; then
  exit 1
fi
[[ -n $FAKE_PICK ]] || exit 1
printf '%s' "$FAKE_PICK"
SH
```

**Pattern for the new stub** — same three states (unset = Esc/tripwire, set-empty = exit-0 empty submit, set = answer), per-invocation knobs `FAKE_INPUT`/`FAKE_INPUT2` counted off the just-logged `menu-input:` line — the exact convention the ffmpeg stub's pass-2 arm uses (`n=$(grep -c ' -pass 2 ' "$CALLS")` at `:79` feeding `FAKE_OUT_BYTES`/`FAKE_OUT_BYTES2`):

```bash
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

- Logs with `%s`/`$*` raw like the menu-select stub — **not** `%q`. `%q` would emit `$'\t'` escapes and break literal-tab `grep -F` matches (research-verified live).
- Log BEFORE the decision so an unexpected call still leaves evidence — dual-purpose tripwire, same as menu-select.
- `FAKE_INPUT2` unset on a second call exits 1 — reads naturally as "user Esc'd the re-prompt" (correct default for single-answer rows).
- Lands anywhere before `chmod +x "$STUB_DIR"/*` (`:173`); `run_transcode` (`:180-189`) needs no changes — env prefixes reach stubs already.
- **Same commit as the feature** — Pitfall 11: the real binary spin-waits `done_file` forever; an unstubbed suite hangs, never fails.

### 3b. Assertion idioms to reuse (all existing)

- **Interactive ≡ CLI parity:** `grep '^ffmpeg ' "$calls" >file` + `cmp -s` against a saved `--target` run's argv — the `expected-medium-argv` + `cmp` shape at `:200-225`. Strongest pin is notification parity: `notification:` lines `cmp`-identical between Custom-pick and `--target 25M` runs.
- **Row presence:** literal `grep -F $'\tCustom size…\t<subtext>'` against the `menu-select:` line; `--default-index 1` retained.
- **gif absence:** `! grep -F 'Custom' "$calls"` on a gif run.
- **Esc/cancel:** `FAKE_PICK=""` + `notification:`/`ffmpeg` emptiness. Pre-notification abort is the sibling-prompt convention.
- **Probe counts:** the happy Custom path logs **4** `^ffprobe:` lines (2 menu-estimate probes `:253-258` + 2 planner probes `:350-352`) — NOT the CLI's "exactly 2". Esc-on-input = 2; budget-exhausted = 2.
- **Knob invocation:** `FAKE_INPUT=25M FAKE_DURATION=60 FAKE_PICK=$'Custom size…\t<subtext>' run_transcode in.mov mp4 1080p` — keep 3 positionals so only the quality menu fires.

### 3c. Deferred closures natural to this commit (from `08/deferred-items.md`)

- **IN-01:** add `""` to the `--target` reject loop at `:872` (`for bad in abc -5M 0 25.5.2M`) — one token; exits 2, `Invalid target size: ` on stderr.
- **IN-03:** `plan_target`'s floor `case` (`:364-368`) lacks `*)` — add `*) echo "Invalid video resolution: $res" >&2; return 1 ;;`. The helpers are now genuinely multi-caller; one line while the file is open.
- IN-02/IN-04/IN-05/IN-06: untouched by this phase's edit sites — leave deferred.

---

## 4. Anti-patterns — what NOT to do

| Anti-pattern | Why it fails | Source |
|---|---|---|
| Adding `custom`/`Custom size…` to the tier `case` whitelist | Leaks a non-tier token toward `transcode_video`'s quality case and `output_path`'s suffix — Pitfall 8 (FATAL) | research/PITFALLS.md:163-182 |
| Branching before the `${selection%%$'\t'*}` strip or after the `case` | Sentinel must match the stripped label; post-case is unreachable | `:279-280` ordering |
| Inserting the row before/among tiers | `--default-index 1` is positional — steals medium's pre-highlight | `:277`, MenuModel.js:497-503 |
| Appending the row ungated | gif menu gains a dead `-b:v` row (D-00a) | `:263` gif arm exists |
| Subtext-less sentinel row | `rowHeightForDetail` renders it shorter — "looks broken" class v1.1 fixed | Menu.qml:147-148 |
| `[[ -z $answer ]] && return 1` (empty submit = cancel) | Real binary exits **0** with `\n` on empty submit — inverts SC-3 | `omarchy-menu-input:54`; Menu.qml:118-136 |
| Re-prompt wrapping `plan_target` | D-01: refusal is a verdict, not a typo; re-prompt budget covers parse failures only | 09-CONTEXT D-01 |
| `local bytes=$(parse_target_size …)` | `local` masks status → garbage flows, re-prompt never fires | `:348-349` comment convention |
| Leaving `quality="target:26214400"` | Corrupts filename + rejected as a tier | `:616`, `:632` |
| Stray stdout inside `select_quality`/`prompt_target_size` | Runs in `$(…)` — anything but the final `printf` corrupts `quality` | `:287`, `:603` |
| `while :` + counter re-prompt | Bound must be visible in the construct — the `for attempt` idiom | `omarchy-launch-shell:40` |
| Unstubbed `omarchy-menu-input` | Real binary spins `done_file` forever — suite hangs, never fails | `omarchy-menu-input:50-52`; Pitfall 11 |
| `%q` logging in the menu-input stub | Emits `$'\t'` escapes; breaks `grep -F $'\t…'` row pins | menu stubs log `%s` raw (`:111`, `:138`) |
| `Custom size...` (three dots) | Label match is byte-exact; `…` is one U+2026 — single-source `$custom_label` | §2a |
| Copying the CLI's "exactly 2 ffprobe" pin | Interactive path probes 4× (2 menu-estimate + 2 planner) | `:253-258` + `:350-352` |
| `--width` required on `omarchy-menu-input` | Optional; default matches the select menu | `:20-27` |
| Touching `usage()`/`args=`/`examples=` | No new CLI surface — menu-only feature; `test/cli` pins unchanged | `:6-7`, `:11-33` |

---

## 5. Patterns the planner must use — compact list

1. **Sentinel row:** `[[ $format == "mp4" ]] && rows+=($'\t'"$custom_label"$'\t'"$custom_subtext")` appended after the tier `done` (`:275`), before `selection=` (`:277`); label/subtext single-sourced in the `:250` locals.
2. **Sentinel branch:** `if [[ $selection == "$custom_label" ]]` immediately after `selection="${selection%%$'\t'*}"` (`:279`), before the tier `case` — `bytes=$(prompt_target_size) || return; printf 'target:%s' "$bytes"; return`.
3. **New helper `prompt_target_size`:** placed right after `parse_target_size` (`:324`), bounded `for attempt in 1 2` (the `compositor_alive` idiom), `answer=$(omarchy-menu-input "$prompt") || return 1`, `if bytes=$(parse_target_size "$answer")`, mutate `prompt` to the D-02 hint between iterations, fall through to `return 1`.
4. **`main()` unwrap inside the `:602-604` gate:** `target_bytes="${quality#target:}"; target_token=$(numfmt --to=iec "$target_bytes"); quality=""` — then zero further main edits; `:610-633` is the Phase-8 path.
5. **Cancel semantics:** exit 1 = Esc (`|| return`/`|| return 1`); exit 0 + empty string = empty submit → parse fails → re-prompt. Never conflate.
6. **Capture discipline:** `var=$(…)` on its own line or inside `if` — never `local var=$(…)`.
7. **Reused verbatim, zero edits:** `parse_target_size`, `plan_target`, `transcode_video_target`, `output_path`, `omarchy-menu-input`, `omarchy-menu-select`, all QML. `usage()`/metadata unchanged.
8. **Stub:** `omarchy-menu-input` stub with `FAKE_INPUT`/`FAKE_INPUT2` + `menu-input: %s` log line, unset=exit-1 tripwire — same commit as the feature (Pitfall 11).
9. **Test pins:** `cmp` ffmpeg+notification lines vs the `--target 25M` run (D-00f); 4 `ffprobe:` on the happy path; `! grep -F 'Custom'` on gif; literal-tab `grep -F` row pins; IN-01/IN-03 closures folded in.
10. **Comment style:** multi-line `#` rationale blocks above each helper/branch explaining the *why* (the file's own convention — see `:302-307`, `:326-336`, `:387-397`), not restating the code.

## Metadata

**Analog search scope:** `bin/` (all `omarchy-menu-*` callers + retry loops), `test/shell.d/`, `docs/menu.md`, `.planning/research/`, `.planning/phases/08-*`
**Files scanned:** ~30 (22 `omarchy-menu-select` call sites reviewed; zero `omarchy-menu-input` callers exist — first consumer)
**Pattern extraction date:** 2026-09-17
