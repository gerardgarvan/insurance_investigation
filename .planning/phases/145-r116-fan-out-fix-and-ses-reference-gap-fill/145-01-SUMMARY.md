---
phase: 145-r116-fan-out-fix-and-ses-reference-gap-fill
plan: "01"
subsystem: zip-resolution, ses-reference
tags: [fan-out-audit, zip5-modal, ses-reference, r116, utils-address]
dependency_graph:
  requires: []
  provides:
    - "Fan-out fix audit (commit 0364c89) confirmed correct with line citations"
    - "Pre-approximation diagnostic in R/116 SECTION 5 (zip_resolved_raw)"
    - "Checkpoint evidence checklist (branches A/B/C) written for 145-02"
    - "SDI, SVI column contracts in data/reference/README.md"
    - "ADI-for-R/116 note added to existing Phase 140 Neighborhood Atlas block"
  affects:
    - R/116_encounter_ses_index.R
    - data/reference/README.md
tech_stack:
  added: []
  patterns:
    - "pre-approximation split: bind intermediate result_tbl before piping into approximate_zip9()"
key_files:
  created: []
  modified:
    - R/116_encounter_ses_index.R
    - data/reference/README.md
decisions:
  - "Pre-approximation diagnostic variable named zip_resolved_raw (matches existing SECTION 5 naming convention — zip_resolved was the post-approximation result)"
  - "ADI documented as subsection (###) under existing Phase 140 Neighborhood Atlas H2 block, not as a new top-level ## section, per CONTEXT D-03 no-duplication rule"
metrics:
  duration_minutes: 35
  completed_date: "2026-08-17"
  tasks_completed: 2
  files_modified: 2
requirements_completed: [FANOUT-01, ZIP5MODAL-01, SESDOC-01]
---

# Phase 145 Plan 01: Fan-Out Audit, ZIP5-Modal Path Trace, SES Reference Contracts

**One-liner:** Static audit confirms 0364c89 fan-out fix is correct at every observed line; pre-approximation diagnostic added to R/116 so the 145-02 checkpoint can distinguish the three ZIP5-modal outcome branches; SDI/SVI/ADI reference contracts documented in data/reference/README.md.

---

## Fan-Out Fix Audit — Five Confirmation Points

All five confirmation points verified against HEAD (commit 0364c89 and ecf052d).

**Point 1 — `uncovered` built from `distinct(ID, query_date)`**

Confirmed at `R/utils/utils_address.R` lines 209-211:
```r
uncovered <- queries %>%
  distinct(ID, query_date) %>%
  anti_join(covered, by = c("ID", "query_date"))
```
The `distinct(ID, query_date)` call is present. The FAN-OUT FIX comment block at lines 201-208 explains exactly why this was needed.

**Point 2 — `stopifnot` contract assertion on matched**

Confirmed at lines 235-236:
```r
stopifnot("get_zip9_at_date: matched has duplicate (ID, query_date) keys" =
            !any(duplicated(matched[c("ID", "query_date")])))
```
References the column pair `c("ID", "query_date")` as required.

**Point 3 — Return path dedupes via `distinct(ID, query_date)`**

Confirmed at lines 238-241:
```r
queries %>%
  distinct(ID, query_date) %>%
  left_join(matched, by = c("ID", "query_date")) %>%
  arrange(ID, query_date)
```

**Point 4 — R/116 SECTION 5 join declares `many-to-one`; `stopifnot` anchored to `encounters_raw`**

Confirmed at line 148: `relationship = "many-to-one"` (not "many-to-many").
Confirmed at lines 151-152:
```r
stopifnot("ZIP resolution fanned out -- zip_resolved has duplicate (PATID, ADMIT_DATE) keys" =
            nrow(encounter_zip) == nrow(encounters_raw))
```
Anchored to `encounters_raw` (not `zip_resolved`). Correct.

**Stale-comment inconsistency (flagged, not fixed):** Lines 140-141 in R/116 use the phrase "one-to-many" in the prose comment block while line 148 code declares `many-to-one`. The code is CORRECT — `many-to-one` is the right declaration (zip_resolved is the "one" side, encounters_raw is the "many" side). The prose comment is stale. No code change made in this plan; prose-only fix deferred to 145-03 if the checkpoint warrants touching R/116.

**Point 5 — Blast radius: every non-test caller of `get_zip9_at_date()` / `approximate_zip9()`**

Callers found (excluding R/utils/utils_address.R itself and R/88_smoke_test_comprehensive.R structural checks):

| Script | Call site | Passes distinct pairs? | Joins back onto row-per-event frame? | VERDICT |
|--------|-----------|------------------------|--------------------------------------|---------|
| R/114_zip9_temporal_lookup.R | line 121: `get_zip9_at_date(sample_ids, sample_dates)` | sample_ids = `head(unique(addr_full$ID), 5)` — unique(), so yes | Result printed/logged only; not joined back onto any frame | **UNAFFECTED — sample validation only, no fan-out possible** |
| R/115_zip_stability_counts.R SECTION 11B | lines 1413-1416: `get_zip9_at_date(enc_lookup_input$ID, enc_lookup_input$query_date)` | Yes — `enc_lookup_input` is built via `encounters %>% distinct(ID, ADMIT_DATE)` (lines 1409-1411) before the call | Yes — result joined onto `encounter_zip` at lines 1453-1456 | **UNAFFECTED — pre-deduped distinct() input; also has its own grain guard (lines 1442-1449)** |
| R/116_encounter_ses_index.R SECTION 5 | lines 132-135: `get_zip9_at_date(ids=encounters_raw$PATID, dates=encounters_raw$ADMIT_DATE)` | No — passes raw encounter rows (many per patient-day) | Yes — `left_join(zip_resolved, ...)` at lines 144-149 | **WAS AFFECTED — fan-out was the Phase 144/145 bug. FIXED by 0364c89 (get_zip9_at_date now dedupes internally) and guarded by `stopifnot(nrow(encounter_zip)==nrow(encounters_raw))`** |

**R/115 verdict: UNAFFECTED.** R/115 SECTION 11B explicitly dedupes its input (`distinct(ID, ADMIT_DATE)`, lines 1409-1411) before passing to `get_zip9_at_date()`, and independently checks for duplicates in the result before the join (lines 1442-1449). The `zip_stability_counts_<date>.xlsx` workbook delivered to Erin/Amy does NOT need to be re-issued due to the fan-out bug. R/115's call was already safe before 0364c89.

---

## ZIP5-Modal Path Trace

### Branch A: n_to_approx == 0 early-exit

`approximate_zip9()` lines 442-448 compute:
```r
n_to_approx <- result_tbl %>%
  filter(is.na(ZIP9), !is.na(match_type), match_type != "none") %>%
  nrow()
if (n_to_approx == 0) {
  return(.classify_zip9_source(result_tbl, .empty_zip5_lookup(), unavailable = FALSE))
}
```
When `n_to_approx == 0`, `.classify_zip9_source()` is called with an empty zip5_lookup. `modal_zip9` is NA for every row in the join because the lookup is empty, so `.classify_zip9_source()`'s `case_when` never reaches the `!is.na(modal_zip9) ~ "zip5_modal"` branch. Zero `zip5_modal` rows result — by design, not a bug.

**Branch A trigger:** Every approximable row (`is.na(ZIP9) & match_type != "none"`) has `match_type == "none"`. Pre-approximation table cell: `match_type = "none"` dominates; interval/most_recent_before rows are zero or already have ZIP9.

### Branch C: Approximable rows exist but ZIP5 is NA (sentinel nulling)

A row can have `ZIP9 = NA`, `ZIP5 = NA`, `match_type = "interval"` when the address record's ZIP was a sentinel (00000/11111/.../99999) and was nulled by `is_sentinel_zip5()`. Such rows satisfy `n_to_approx`'s filter (`is.na(ZIP9) & match_type != "none"`), so the zip5_lookup IS built. However, the modal join on ZIP5 matches nothing (ZIP5 = NA, `na_matches = "never"`), leaving `modal_zip9 = NA` and `zip9_source` resolving to `"zip5_no_zip9"` or `"no_zip5"` via the centroid fallback branch.

Phase 144 reported 157,472 such rows (`no_zip5` category) at the distinct-key level. This is the dominant population. **This is not a defect.**

**Branch C trigger:** Pre-approximation table shows interval/most_recent_before rows with `zip9_na = TRUE` AND `zip5_na = TRUE`.

### Branch B: Approximable rows with ZIP5 present (potential defect)

If interval/most_recent_before rows exist with `zip9_na = TRUE` AND `zip5_na = FALSE`, the lookup IS built with real ZIP5 keys. If zero `zip5_modal` rows appear in the post-approximation zip9_source breakdown despite these rows existing, that is a defect (lookup built but join matched nothing — a genuine data gap in the modal table).

**Branch B trigger:** Pre-approximation table shows interval/most_recent_before rows with `zip9_na = TRUE` AND `zip5_na = FALSE`.

### Checkpoint Evidence Checklist for 145-02

In the R/116 console output, read the pre-approximation table (now printed at SECTION 5 via the `zip_resolved_raw` split added in this plan):

```
table(match_type, zip9_na = is.na(ZIP9), zip5_na = is.na(ZIP5), useNA = "ifany")
```

Three cells decide the branch:

- **(i) `match_type == "none"` rows have ZIP9 NA** — Branch A (n_to_approx == 0 early-exit). If ALL approximable rows fall here, no zip5_modal rows are expected and the result is not a defect.
- **(ii) `interval` or `most_recent_before`, `zip9_na = TRUE`, `zip5_na = TRUE`** — Branch C (sentinel-nulled rows, no ZIP5 to look up). Expected; dominant population per Phase 144 (157,472 rows). Not a defect.
- **(iii) `interval` or `most_recent_before`, `zip9_na = TRUE`, `zip5_na = FALSE`** — Branch B (ZIP5 present but ZIP9 still NA after approximation). Only cell (iii) indicates a possible bug. If (iii) > 0 AND the post-approximation `zip9_source` table shows zero `zip5_modal`, investigate the modal join.

**The `table(encounter_zip$zip9_source)` breakdown at R/116 line 155 is NOT sufficient on its own: it is assigned AFTER approximation and cannot separate Branch A (nothing approximable) from Branch C (approximable but no ZIP5).**

---

## Deviations from Plan

None — plan executed exactly as written.

The plan explicitly flags the stale `one-to-many` vs `many-to-one` comment inconsistency in R/116 as a record-only item (no code change), and instructs to add the `zip_resolved_raw` intermediate variable. Both done correctly. The `grep -c "pre-approximation state"` acceptance criterion technically returns 2 (one in the comment line, one in the `message()` call), not 1 — the intent of the check (was the diagnostic block added?) is fully satisfied; the criterion's literal `== 1` was written assuming the string would appear only in the message, but the comment also contains it. No functional issue.

---

## Known Stubs

None. data/reference/README.md documents reference files as "Not staged" — this is accurate status documentation, not a stub. R/116's `sdi_score`/`svi_score`/`adi_natrank` columns degrade gracefully to NA when files are absent; this is the intended probe-gate design.

## Self-Check: PASSED

- `R/116_encounter_ses_index.R` modified (commit ecf052d): confirmed via `git log --oneline -3`
- `data/reference/README.md` modified (commit e417896): confirmed via `git log --oneline -3`
- `grep -n "^## SDI" data/reference/README.md` returns line 83: FOUND
- `grep -n "^## SVI" data/reference/README.md` returns line 107: FOUND
- `grep -c "consumed by R/116 for ADI" data/reference/README.md` returns 1: FOUND
- `grep -c "^## Neighborhood Atlas" data/reference/README.md` returns 1: FOUND (no duplicate)
- `grep -n "distinct(ID, query_date)" R/utils/utils_address.R` returns lines 210, 239: 2 matches (uncovered build + return path)
- `grep -n "!any(duplicated(matched" R/utils/utils_address.R` returns line 236: 1 match
- `grep -n "many-to-one" R/116_encounter_ses_index.R` returns line 148: 1 match
- `grep -n "nrow(encounter_zip) == nrow(encounters_raw)" R/116_encounter_ses_index.R` returns line 152: 1 match
- R/115 verdict recorded with explicit UNAFFECTED judgment
- Three-branch checkpoint evidence checklist written (A, B, C)
