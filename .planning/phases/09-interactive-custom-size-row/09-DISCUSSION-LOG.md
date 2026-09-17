# Phase 9 Discussion Log

**Date:** 2026-09-17
**Phase:** 9 — Interactive `Custom size…` row

## Process

Phase 9's scope was largely pre-locked by ROADMAP.md (sentinel row, `omarchy-menu-input` handoff, `target:<bytes>` return contract, re-prompt-once, Esc-cancel, zero QML/menu-select changes, harness stub requirement) plus the Phase 8 contract it reuses. Analysis surfaced 2 genuine gray areas; both were presented with pros/cons and recommendations, and both recommendations were accepted without modification.

## Decisions

### D-01: Floor refusal UX — abort like CLI
**Question:** A parseable-but-too-small input (e.g. `10M` under the floor) — re-prompt or abort?
**Options presented:**
1. Abort like CLI — planner refusal is terminal; error names the achievable minimum (recommended)
2. Re-prompt with floor — reopen input with the minimum in the prompt; needs refusal text plumbed back through `select_quality`
**Chosen:** Option 1. Rationale: the re-prompt budget is for typos; a floor refusal is information to absorb, and `plan_target` stays identical across entry points.

### D-02: Re-prompt affordance — error hint in prompt
**Question:** On empty/unparseable input, does the second prompt change its text?
**Options presented:**
1. Error hint in prompt — `Invalid size — e.g. 25M` (recommended)
2. Identical prompt — simplest, but reads like a no-op
**Chosen:** Option 1.

## Scope Notes

- No scope creep surfaced; deferred list records re-prompt-on-refusal, prefilled last size, and gif custom-size row as future considerations.
- IN-01/IN-03 from Phase 8's deferred-items.md noted as natural closures for this phase (second caller of `parse_target_size`/`plan_target`).
