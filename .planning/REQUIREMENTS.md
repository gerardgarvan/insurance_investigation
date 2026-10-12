# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

## v3.9 Pipeline Hygiene

**Milestone goal:** Close small loose ends from v3.5–v3.8 so the smoke test and ZIP work are trustworthy. No new analysis.

### HYGIENE-01 — Smoke-Check Discrepancy Resolution

Resolve the 920 PASS / 921 total discrepancy in R/88. Identify the one check that is not PASS (failed, skipped, or uncounted). Fix it or document it with a clear reason in the SUMMARY.

- **Phase**: 174
- **Status**: Pending

### HYGIENE-02 — R/88 Exit-Status Hardening

Make R/88 signal failure when any check fails. After the summary block: if `failed > 0` and `!interactive()`, call `quit(status = 1)`; in interactive sessions print a prominent "R/88 FAILED: N checks" line. Verify skip branches do not add to PASS count. Verify all per-section counters feed the global passed/failed totals.

- **Phase**: 175
- **Status**: Pending

### HYGIENE-03 — Phase 151 Close-Out

Run `R/121_zip_problem_inventory.R` on HiPerGator; check outputs against `151-PLAN.md` success criteria; write `151-01-SUMMARY.md`; tick Phase 151 in ROADMAP. If outputs fall short of criteria, record the gap and leave Phase 151 open.

- **Phase**: 176
- **Status**: Pending

### HYGIENE-04 — NEEDS_TEMPORAL_MATCH Sizing Memo

Using the latest R/116 encounter-level output, count encounters where `zip9_source == "none"` OR ZIP5 is missing. Split by R/121 groups NEEDS_TEMPORAL_MATCH (~410 patients) and UNREACHABLE_NO_ZIP9 (~427 patients). Report encounters and patients per group plus share of all cohort encounters. Produce a short decision memo recommending whether a new imputation tier is worth a dedicated phase, citing the Phase 150 concordance (547 concordant / 135 discordant, ~80%) as the expected error rate for any new tier. Read-only analysis; do not implement the tier.

- **Phase**: 177
- **Status**: Pending

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| HYGIENE-01 | Phase 174 | Pending |
| HYGIENE-02 | Phase 175 | Pending |
| HYGIENE-03 | Phase 176 | Pending |
| HYGIENE-04 | Phase 177 | Pending |
