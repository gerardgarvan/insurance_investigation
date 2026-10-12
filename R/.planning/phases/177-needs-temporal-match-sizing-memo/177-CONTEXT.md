# Phase 177: NEEDS_TEMPORAL_MATCH Sizing Memo — Context

**Gathered:** 2026-10-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a sizing memo that answers: how many analytic-universe encounters would a temporal-match imputation tier actually fill, and does that volume warrant a new phase?

Deliverables are a small re-runnable R script (`R/177_temporal_match_sizing.R`) and a short markdown memo in the phase directory. No pipeline mutations — read-only analysis only.

</domain>

<decisions>
## Implementation Decisions

### D-01: Encounter universe — two rows, each with a different purpose

Report two encounter counts, each serving a different question:

**Context row** — all encounters belonging to `NEEDS_TEMPORAL_MATCH` patients (triage column from R/121 `$patients`). Joined from the encounter table on PATID. This gives the exposure: how many encounters are in play for this patient group.

**Decision row** — encounters a temporal match would *actually change*. An encounter qualifies when:
- ZIP5 is missing on that encounter row, AND
- At least one dated address-history row covers the encounter date (i.e., a temporal lookup could fill it).

The analytic universe for the decision row is the **Phase 165 per-encounter distance set** — that is where a fix would move a distance result. Report both:
- Whole-record count (all qualifying encounters)
- Post-anchor count (encounters within the Phase 165 anchor window, mirroring the two Phase 165 flags)

An encounter-level join requires a script; R/121 alone cannot answer this.

### D-02: Deliverable form

**Script:** `R/177_temporal_match_sizing.R` — read-only, no pipeline mutations.
- Writes a counts-only workbook to `output/`, with `suppress_small` applied and KEY sheet leftmost.
- Patient-level detail goes to `output/internal/`.
- Register in R/39 and SCRIPT_INDEX as a one-off investigation.
- Do NOT add a new R/88 section.

**Memo:** A markdown memo in the phase directory (`177-SIZING-MEMO.md`) that cites the numbers produced by the script. The memo is the human-readable recommendation; the script is the reproducible audit trail.

### D-03: Recommendation framework — thresholds set before the counts arrive

Primary measure: share of analytic-universe encounters (Phase 165 set) that a temporal match would fill. Secondary: share of patients affected, and a rough implementation-cost note (most logic probably already exists in `utils_address.R` from Phase 139's temporal lookup).

Also count how many filled encounters would land >100 mi — this flag drives the CBC test and could materially change that result.

**Pre-set decision thresholds (write into the memo before populating numbers):**

| Share of analytic encounters filled | Effect on >100 mi result | Recommendation |
|---|---|---|
| Under 1 % | Can't plausibly move it | Document only |
| 1 – 5 % | — | Inline fix in an existing script |
| Over 5 % | *Or* could change the >100 mi result | New phase |

Thresholds are locked here so the recommendation cannot be chosen after seeing the counts.

### D-04: R/122 cross-check — reconciliation required before recommendation

Confirm that R/121's `NEEDS_TEMPORAL_MATCH` patient count (expected ~410 from the prior run) agrees with the `patient_zip_missing` waterfall step in R/122 (encounters where `distance_status == "patient_zip_missing"`), or explain the gap using the definitional difference (patient-level triage vs. encounter-level distance status).

This is a few lines in the script. If the counts disagree without a clear definitional explanation, the memo must say so explicitly before making any recommendation, because the sizing would rest on a count that may be wrong.

### Claude's Discretion

- Exact column names and join keys used to link R/121 `$patients` to the encounter universe (read from the actual RDS before coding).
- Whether the script sources `R/00_config.R` directly or via `source("R/utils/utils_address.R")` — follow whichever pattern adjacent scripts use.
- Workbook sheet naming and column layout (follow Phase 121 / Phase 122 conventions).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary analysis inputs
- `R/121_zip_problem_inventory.R` — defines the five triage groups; the `$patients` RDS element is the join key source
- `R/122_encounter_distance.R` — defines `distance_status` and the `patient_zip_missing` waterfall used for the R/122 cross-check (D-04)

### Analytic universe definition
- Phase 165 per-encounter distance set — this is the analytic universe for the decision row (D-01); confirm the output path from the Phase 165 phase directory or R/165 script

### Utility / config
- `R/utils/utils_address.R` — contains the temporal lookup logic from Phase 139; likely reusable for the decision-row filter
- `R/00_config.R` — defines `CONFIG$output_dir`, `suppress_small`, and other shared constants

### Registration targets (read-only, do not modify during this phase)
- `R/39_script_registry.R` (or equivalent) — register `R/177_temporal_match_sizing.R` as a one-off investigation
- `SCRIPT_INDEX.md` (or equivalent) — add entry for R/177

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `utils_address.R` temporal lookup (Phase 139): carries the logic to test whether a dated address-history row covers an encounter date — directly applicable to the D-01 decision-row filter.
- R/121 `$patients` and `$roster` RDS elements: patient-level triage and address roster already computed; Phase 177 is read-only downstream.
- R/122 `patient_zip_missing` waterfall counts: available from the R/122 output workbook or by re-reading `enc_distance` from its RDS.

### Established Patterns
- Workbook output: `openxlsx`, KEY sheet leftmost, `suppress_small` applied to any patient-count cells.
- Patient-level data → `output/internal/`; aggregate counts → `output/`.
- Script registration: R/39 + SCRIPT_INDEX entry with a `one-off-investigation` tag.

### Integration Points
- R/177 reads from R/121 RDS and the Phase 165 distance set; writes to `output/` and `output/internal/`. No script writes to these inputs.
- The markdown memo (`177-SIZING-MEMO.md`) is committed to the phase directory; it is not a pipeline output.

</code_context>

<specifics>
## Specific Ideas

- The >100 mi count is specifically called out because it drives the CBC (complement-binding capacity?) test — make this a named row in the workbook, not just a footnote.
- The recommendation table (thresholds D-03) should appear verbatim in the memo *before* the actual count rows, so the logic is transparent and the decision can be audited.
- If the R/121 vs R/122 reconciliation (D-04) shows a gap, the memo should quantify the definitional difference (e.g., "R/121 counts patients; R/122 counts encounter rows; the gap of N is explained by patients with multiple missing-ZIP5 encounters").

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 177-needs-temporal-match-sizing-memo*
*Context gathered: 2026-10-12*
