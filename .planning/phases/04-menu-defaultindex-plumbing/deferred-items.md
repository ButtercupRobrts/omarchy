# Deferred Items — Phase 4

## Out-of-scope discoveries

- **`--width` / `--maxheight` non-finite values emit invalid JSON** (`bin/omarchy-menu-select:95-96`): `int($ARGV[4])`/`int($ARGV[5])` numify caller strings; `1e1000`/`inf`/`nan` produce bare `Inf`/`NaN` tokens → `JSON.parse` throws in `Menu.qml:23` → payload discarded → menu opens in wrong mode → `doneFile` never created → the script spins forever. Pre-existing defect the `--default-index` arm replicated (fixed there in `fix(04-01)`); the sibling arms remain latent. Source: `04-REVIEW.md` WR-01. Candidate fix: apply the same `("$v" =~ /^-?[0-9]+$/) ? $v + 0 : 0` guard to width/maxHeight emission.
