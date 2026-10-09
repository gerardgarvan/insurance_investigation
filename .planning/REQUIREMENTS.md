# Milestone v3.8 Requirements
# Pipeline Refresh & Phase 130 Close-out

## Active Requirements

### Pipeline Refresh (closes Phase 163/164 runtime gates)

- [ ] **RFSH-01:** Re-run R/147 on HiPerGator after Phase 163 changes; run `R/147_verify_vs_1006.R` against the 1006 reference workbook (all checks pass) and confirm R/88 Section 15ao passes
- [ ] **RFSH-02:** Re-run R/166, R/167, R/168 after the clean R/147 output; verify primary-tier results and CIF are identical to the 10-08 workbook; confirm only Echo/ECG/Mammogram/PFT any-tier rates shift
- [ ] **RFSH-03:** Close Phase 164 HiPerGator checkpoint (Dox rename in Gantt); re-run R/170; verify matched rows are identical and document that any `n_norm_only`/`n_mismatch` shifts involve doxorubicin/Adriamycin only

### Phase 130 Close-out (v3.3 deferred)

- [ ] **DOI-REG-01:** Add R/111 and R/112 to R/39 and SCRIPT_INDEX
- [ ] **DOI-REG-02:** Add R/88 smoke section for DoI scripts (structural checks already validated locally)
- [ ] **DOI-REG-03:** HiPerGator runtime gate — confirm R/111 and R/112 run cleanly against real data and workbook renders

## Future Requirements

- Move `EXCLUDED_CDM_TABLES` into `load_surveillance_codeset()` in `utils_surveillance.R` so R/147 and R/166 share a single source of truth (stability milestone)
- R/165 CBC re-derivation: read R/147 output RDS instead of re-deriving from DuckDB to avoid silent drift (stability milestone)

## Out of Scope

- New analytical deliverables (deferred to v3.9 pending team asks from refreshed workbooks)
- v3.4 code review remediation (stability milestone, separate track)
- ZIP/SES enrichment (deferred)

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| RFSH-01 | Phase 170 | pending |
| RFSH-02 | Phase 171 | pending |
| RFSH-03 | Phase 172 | pending |
| DOI-REG-01 | Phase 173 | pending |
| DOI-REG-02 | Phase 173 | pending |
| DOI-REG-03 | Phase 173 | pending |
