# Archived R Scripts

Scripts in this directory are **no longer part of the active pipeline** but are preserved for reference. They represent one-off investigations, superseded implementations, or HiPerGator orchestration helpers that are environment-specific.

**Do not source() these scripts from active pipeline code.**

---

## Archived Scripts

### check_deleted_proton_code.R
- **Purpose:** One-off check for deleted proton therapy CPT code 77521 in PROCEDURES table
- **Why Archived:** Single-use diagnostic; CPT code deletion date verified; no ongoing use
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 00_config, 01_load_pcornet
- **Safe to Delete:** Yes (one-off audit, results already captured)

### date_range_check.R
- **Purpose:** Quick diagnostic for earliest DIAGNOSIS date and latest TUMOR_REGISTRY dates
- **Why Archived:** One-time data exploration; date ranges documented; not part of production pipeline
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 00_config, 01_load_pcornet
- **Safe to Delete:** Yes (exploratory only)

### payer_frequency_from_resolved.R
- **Purpose:** Generate payer frequency table from 60_tiered_same_day_payer.R resolved detail CSV output
- **Why Archived:** Reads from CSV output file; not part of main pipeline flow; superseded by integrated analysis
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** Reads CSV directly (no R script dependencies)
- **Safe to Delete:** Yes (can be recreated from output CSV if needed)

### run_phase12_outputs.R
- **Purpose:** HiPerGator execution helper: orchestrates Phase 12 output generation (4 PNGs + PPTX)
- **Why Archived:** Environment-specific HiPerGator orchestration; superseded by updated script numbers
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 75_encounter_analysis, 72_generate_pptx (uses old source paths)
- **Safe to Delete:** No (may be adapted for future HiPerGator batch runs)

### sct_code_inventory.R
- **Purpose:** SCT evidence inventory: all codes from every PCORnet source table per patient per date
- **Why Archived:** One-off investigation for stem cell transplant code coverage; findings captured
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 00_config, 01_load_pcornet
- **Safe to Delete:** Yes (one-off audit, results already used in treatment analysis)

### search_C8190.R
- **Purpose:** One-off ICD code search for C8190 (unspecified Hodgkin lymphoma) in diagnosis data
- **Why Archived:** Single-use diagnostic; ICD code presence confirmed/denied
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 00_config, 01_load_pcornet
- **Safe to Delete:** Yes (one-off search)

### tiered_payer_summary.R
- **Purpose:** Generate styled xlsx summary from 60_tiered_same_day_payer.R CSV outputs
- **Why Archived:** Post-processing helper; reads CSV outputs rather than integrating into pipeline
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 00_config (reads CSV files from output/)
- **Safe to Delete:** No (useful for regenerating formatted reports from tiered payer CSVs)

### treatment_cross_reference.R
- **Purpose:** Two-way gap report comparing reference document code lists against live TREATMENT_CODES config
- **Why Archived:** QA validation tool; useful for periodic audits but not routine pipeline execution
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 00_config, 01_load_pcornet
- **Safe to Delete:** No (useful for future treatment code audits when reference docs are updated)

---

**Note:** Scripts marked "Safe to Delete: No" should be retained for potential reuse in future analyses or batch execution workflows.
