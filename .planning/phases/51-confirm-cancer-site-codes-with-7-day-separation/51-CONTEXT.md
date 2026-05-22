# Phase 4: Confirm Cancer Site Codes with 7-Day Separation - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Same confirmation logic as Phase 3 (2+ distinct dates per code per patient), but with the added requirement that the distinct dates must be at least 7 calendar days apart. Produces a standalone styled xlsx with two sheets (exact code and prefix level). This is a separate script from R/50 (Phase 3).

</domain>

<decisions>
## Implementation Decisions

### Script Structure
- **D-01:** Separate R/51 script (next available number). Clone of R/50 with the 7-day gap filter added. R/50 remains untouched as the Phase 3 baseline.
- **D-02:** Output is a standalone xlsx file (e.g., cancer_site_confirmation_7day.xlsx). Same column structure as Phase 3 -- no comparison columns from Phase 3 included. Users compare by opening both xlsx files side by side.

### Confirmation Logic (Carried from Phase 3)
- **D-03:** Two confirmation levels: (1) exact ICD-10 code with 7-day gap, (2) 3-character prefix with 7-day gap. Both computed and reported in separate sheets.
- **D-04:** DIAGNOSIS table only. DX_DATE for distinct-date counting. ICD-10 codes only (DX_TYPE == "10").
- **D-05:** Per cancer site category: total_patients, confirmed_patients, unconfirmed_patients, confirmation_rate. Only populated categories (no zero-count rows).

### 7-Day Gap Definition
- **D-06:** "7 days apart" means max(date) - min(date) >= 7 days for a patient's dates with the same code (or prefix). Standard epidemiological approach -- if the earliest and latest dates are 7+ days apart, the code is confirmed.

### Output Format (Carried from Phase 3)
- **D-07:** Styled xlsx output following openxlsx2 patterns from R/50 (dark header, freeze panes, number formatting, auto column widths, totals row).

### Claude's Discretion
- Exact output filename convention
- Whether to add a subtitle noting the 7-day requirement in the xlsx title rows
- Column ordering and styling details beyond what's established in R/50

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 3 Implementation (Primary Reference)
- `R/50_cancer_site_confirmation.R` -- Complete Phase 3 script to clone and modify. Contains PREFIX_MAP, CATEGORY_ORDER, classify_codes(), DIAGNOSIS query, confirmation logic, and styled xlsx output.

### Phase 3 Context
- `.planning/phases/03-confirm-cancer-site-codes-by-distinct-date-count-a-person-has-a-confirmed-code-if-they-have-at-least-two-distinct-dates-with-the-same-code/03-CONTEXT.md` -- Phase 3 decisions that carry forward.

### Cancer Site Classification
- `R/47_cancer_site_frequency.R` lines 39-309 -- Original PREFIX_MAP source (copied into R/50)

### DuckDB Access
- `R/utils_duckdb.R` lines 100-138 -- `open_pcornet_con()` and `get_pcornet_table()` patterns

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/50_cancer_site_confirmation.R`: Complete script to clone. Contains all shared logic (PREFIX_MAP, CATEGORY_ORDER, classify_codes(), DIAGNOSIS query, xlsx styling). The 7-day filter is a small addition to the confirmation step.

### Key Modification Points
- Section 3 (exact code confirmation): After `distinct(ID, DX_norm, DX_DATE, category)` and `group_by(ID, DX_norm)`, replace `filter(n_distinct(DX_DATE) >= 2)` with logic that checks `max(DX_DATE) - min(DX_DATE) >= 7`
- Section 4 (prefix confirmation): Same modification but grouped by `prefix3` instead of `DX_norm`
- Everything else (PREFIX_MAP, CATEGORY_ORDER, classify_codes, xlsx styling) is identical

### Established Patterns
- R/50 confirmation pattern: group_by(ID, code) -> filter on date criterion -> ungroup -> group_by(category) -> summarise n_distinct(ID)
- openxlsx2 styling: dark header fill, freeze panes, number formatting, totals row

### Integration Points
- Input: DIAGNOSIS table via DuckDB (same as R/50)
- Output: New xlsx in `CONFIG$output_dir` or output/tables/
- No modification to R/50 or other existing scripts

</code_context>

<specifics>
## Specific Ideas

- The implementation is straightforward: clone R/50, modify the two confirmation filter lines to check date span >= 7 days instead of just count >= 2
- The date arithmetic uses base R: `as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7` within the grouped filter
- Sheet titles should reflect the 7-day requirement (e.g., "Cancer Site Confirmation - Exact Code (7-Day Gap)")

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 04-confirm-cancer-site-codes-with-7-day-separation*
*Context gathered: 2026-05-19*
