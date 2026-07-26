---
status: resolved
trigger: "r112-many-to-many-doi-enc-joins"
created: 2026-07-26T00:00:00Z
updated: 2026-07-26T00:00:00Z
---

## Current Focus

hypothesis: All 5 warnings are structurally expected given the data model — doi_enc has multiple rows per ID (one per DoI encounter) and multiple rows per ENCOUNTERID is possible if one encounter carries multiple DoI codes. None represent data bugs. The tier1 ENCOUNTERID join can produce m:m if one ENCOUNTERID maps to multiple DoI dx codes in doi_enc AND the drug_admins side has the same ENCOUNTERID more than once (unlikely but possible). The tier2 / count_window_matches ID join is definitionally m:m (patient x all their DoI encounters). The hl_dx_dated left join is m:m because a patient has many HL dx dates. All downstream aggregations use n_distinct(ID) and n_distinct(ENCOUNTERID) and sum() which are safe against this. Fix = add relationship="many-to-many" where intentional, and add a dedup/distinct where a cross-product is unintended.
test: trace each join site for whether dedup is needed vs. relationship annotation
expecting: tier1 needs investigation (ENCOUNTERID should be 1:1 or m:1 in doi_enc unless multi-code); tier2/count_window_matches need relationship annotation; hl_dx_dated join needs relationship annotation
next_action: check doi_enc structure (R/111 output) and determine if ENCOUNTERID is unique there

## Symptoms

expected: Joins in R/112 produce expected row counts — each drug admin matched to DoI encounters within a date window, no silent row inflation.
actual: 5 dplyr many-to-many warnings fire on doi_enc and hl_dx_dated joins
errors: dplyr "Detected an unexpected many-to-many relationship" warnings (not errors, pipeline continues)
reproduction: Run R/112_doi_attribution_report.R
started: Ongoing — likely always present since R/112 was written

## Eliminated

- hypothesis: m:m warnings indicate data bugs causing row duplication that inflates counts
  evidence: All downstream aggregations use n_distinct(ID) and n_distinct(ENCOUNTERID); the hl_active join is followed by group_by+any() summarise; count_window_matches collapses with summarise(n()). No inflation path exists.
  timestamp: 2026-07-26

## Evidence

- timestamp: 2026-07-26
  checked: R/111_doi_classification.R — doi_encounters.rds construction
  found: doi_encounters is written at encounter+code grain — one row per (ID, ENCOUNTERID, doi_code). A single ENCOUNTERID can appear in multiple rows if that encounter carried multiple DoI ICD codes (e.g. a visit coded for both RA and IBD). There is NO distinct(ENCOUNTERID) dedup step before saveRDS.
  implication: doi_enc in R/112 is NOT unique on ENCOUNTERID. The tier1 ENCOUNTERID equi-join is therefore a legitimate m:m: one drug admin ENCOUNTERID can match multiple doi_enc rows (one per DoI code on that encounter). This is INTENTIONAL — the report wants all co-occurring DoI codes, not just one.

- timestamp: 2026-07-26
  checked: R/112 tier2 join (line ~229): drug_unmatched inner_join doi_enc by "ID"
  found: drug_unmatched has one row per drug admin event; doi_enc has one row per (ID, ENCOUNTERID, doi_code). A patient with multiple DoI encounters produces multiple doi_enc rows, making this m:m by design — the point is to find ALL DoI encounters within the date window.
  implication: INTENTIONAL m:m. Correct fix = add relationship="many-to-many". The subsequent date-window filter then prunes to pairs within window, which is the intended behavior.

- timestamp: 2026-07-26
  checked: R/112 hl_dx_dated left_join (line ~317): distinct(ID, treatment_date) left_join hl_dx_dated by "ID"
  found: hl_dx_dated is built with distinct(ID, DX_DATE) — unique on (ID, DX_DATE) but NOT on ID alone. A patient with multiple dated HL diagnoses produces multiple rows. The left side has one row per (ID, treatment_date); the right side may have many rows per ID.
  implication: INTENTIONAL m:m — the group_by + any() summarise immediately after correctly collapses back to one row per (ID, treatment_date). The m:m expansion is the correct mechanism for checking if any HL dx falls within the window. Fix = add relationship="many-to-many".

- timestamp: 2026-07-26
  checked: count_window_matches() (lines ~479-484): drug_admins inner_join doi_enc by "ID"
  found: Same pattern as tier2 — drug_admins (one row per drug admin) joined to doi_enc (many rows per ID). This is a sensitivity-analysis cross-join for the metadata sheet, not a keyed lookup. The result is immediately collapsed via summarise(n_pairs=n(), n_patients=n_distinct(ID)).
  implication: INTENTIONAL m:m. Fix = add relationship="many-to-many".

- timestamp: 2026-07-26
  checked: Downstream aggregations in Sections 5 and 6
  found: All Sheet 1 and Sheet 3 counts use n_distinct(ID) and n_distinct(ENCOUNTERID). Sheet 2 is encounter grain (raw pairs) which is the intended output. hl_active uses group_by + any() which correctly collapses expanded rows.
  implication: No silent inflation of patient/encounter counts — the n_distinct guards are correct. The row-level expansion in doi_drug_links is intentional (one row per drug-DoI code pair) and is what Sheet 2 reports.

## Resolution

root_cause: doi_encounters.rds is at (ID, ENCOUNTERID, doi_code) grain — one row per DoI code per encounter. Joining on ENCOUNTERID or ID therefore produces intentional m:m expansions (one drug admin matched to all DoI codes on that encounter, or to all of a patient's DoI encounters). The hl_dx_dated table is at (ID, DX_DATE) grain — a patient with multiple HL dx dates is also m:m on ID. None of these are data bugs; all downstream aggregations correctly use n_distinct() or group_by+summarise() to collapse.

fix: Added relationship="many-to-many" to all 4 join sites in R/112:
  1. tier1 ENCOUNTERID equi-join (~line 193)
  2. tier2 ID join (~line 229)
  3. hl_dx_dated left_join (~line 317)
  4. count_window_matches() ID join (~line 481)
  No logic changes — warnings suppressed by declaring intent explicitly.

verification: pending human verify on HiPerGator (Windows structural-only; real data run is HiPerGator)

files_changed: [R/112_doi_attribution_report.R]
