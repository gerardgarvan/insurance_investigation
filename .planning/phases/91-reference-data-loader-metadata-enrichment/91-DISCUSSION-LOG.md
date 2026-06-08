# Phase 91: Reference Data Loader & Metadata Enrichment - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-08
**Phase:** 91-reference-data-loader-metadata-enrichment
**Areas discussed:** F/S/E/N label handling, Multi-code episode display, TBD code export format, Cross-use flag values

---

## F/S/E/N Label Handling

### Question 1: Non-chemotherapy treatment_line value

| Option | Description | Selected |
|--------|-------------|----------|
| NA | Explicit NA for non-chemotherapy codes. Downstream analysts can filter by treatment_type == 'Chemotherapy' when they want line labels. Clean and honest about data scope. | ✓ |
| "N/A" string | Literal 'N/A' text instead of R's NA. Makes it visible in CSV exports that line info doesn't apply (rather than looking like missing data). | |
| Category default | Use the treatment_type as fallback (e.g., 'Radiation', 'SCT'). Ensures column is always populated, but mixes semantics (treatment line vs. treatment type). | |

**User's choice:** NA (Recommended)
**Notes:** F/S/E/N only exists in Chemotherapy sheet (column 8). Radiation (7 cols), SCT (6 cols) lack this column entirely.

### Question 2: F/S/E/N normalization format

| Option | Description | Selected |
|--------|-------------|----------|
| Single uppercase letter | Normalize to exactly F, S, E, or N. Blank/N/A/missing → NA. Clean, compact, easy to filter. Standard for categorical codes in clinical data. | ✓ |
| Full words | Expand to First-line, Second-line, Established, Not-established. More readable in CSV but longer and harder to filter programmatically. | |
| You decide | Claude picks the normalization approach based on what fits the existing Gantt column patterns. | |

**User's choice:** Single uppercase letter (Recommended)
**Notes:** None

---

## Multi-Code Episode Display

### Question 1: Multi-code metadata representation

| Option | Description | Selected |
|--------|-------------|----------|
| Parallel semicolon lists | Match existing triggering_codes pattern: medication_name = 'Ado-Trastuzumab;Brentuximab;Doxorubicin'. Keeps 1:1 positional correspondence with triggering_codes. Established pattern from Phase 64. | ✓ |
| Unique values only | Deduplicate: if 3 codes all have code_type='RXNORM', show 'RXNORM' once instead of 'RXNORM;RXNORM;RXNORM'. Cleaner but loses positional alignment. | |
| Primary code only | Use metadata from the first triggering code only. Simplest but loses information about secondary codes in the episode. | |

**User's choice:** Parallel semicolon lists (Recommended)
**Notes:** Maintains consistency with existing Phase 64 semicolon delimiter pattern.

### Question 2: Treatment line aggregation strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Parallel list (consistent) | F;F;S — matches all other new columns. Analysts can decide how to aggregate. Avoids losing per-code granularity. | |
| Aggregate to best | Single value per episode: F > S > E > N priority. Treatment line IS an episode concept, not per-code. Consistent with existing is_first_line column (boolean, not per-code). | ✓ |
| Both columns | treatment_line_codes = 'F;F;S' (per-code) AND treatment_line = 'F' (aggregated). Maximum information but adds column bloat. | |

**User's choice:** Aggregate to best (Recommended)
**Notes:** Treatment line is an episode-level concept. Aggregation priority: F > S > E > N.

---

## TBD Code Export Format

### Question 1: Export format for SME review

| Option | Description | Selected |
|--------|-------------|----------|
| xlsx with context | Single xlsx sheet listing each TBD code with: code, current category, medication name, patient/record counts from DuckDB, and a 'Classification Question' column describing what needs resolving. Matches the project's existing xlsx export pattern. | ✓ |
| Console log only | Print TBD codes to the R console with message() during script execution. No persistent file — just alerts the analyst when running the pipeline. Lightest touch. | |
| CSV sidecar | Simple CSV next to treatment_episodes.rds listing unresolved codes with metadata. Easier to diff/track in git than xlsx. | |

**User's choice:** xlsx with context (Recommended)
**Notes:** None

### Question 2: TBD codes in main output

| Option | Description | Selected |
|--------|-------------|----------|
| Include with flag | Keep TBD codes in treatment_episodes.rds but add clear marker values (e.g., treatment_line = 'TBD', cross_use_flag = 'TBD'). Analysts see everything; can filter TBD out if needed. No data loss. | ✓ |
| Exclude from main output | Remove TBD code episodes from treatment_episodes.rds entirely. Only in the separate SME xlsx. Cleaner main output but episodes may disappear if their only triggering codes are TBD. | |
| You decide | Claude picks based on downstream impact analysis. | |

**User's choice:** Include with flag (Recommended)
**Notes:** Preserves all data. TBD marker values enable easy filtering.

---

## Cross-Use Flag Values

### Question 1: Column 9 normalization strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Pass through raw values | Read column 9 as-is from the xlsx and store directly. Whatever text is in the cell goes into sct_cross_use_flag. Simplest — preserves the SME's original annotations for Phase 93 to interpret. | |
| Normalize to enum | Map raw values to a fixed set (e.g., 'SCT_conditioning', 'Immunotherapy_dual', 'None', 'TBD'). Cleaner for downstream filtering but requires knowing all possible values upfront. | |
| You decide after inspection | Claude reads the actual xlsx values during implementation and picks the best normalization strategy based on what's found. | ✓ |

**User's choice:** You decide after inspection
**Notes:** Claude's discretion — determined during implementation after inspecting actual column 9 values.

### Question 2: Episode-level cross-use flag aggregation

| Option | Description | Selected |
|--------|-------------|----------|
| Any-positive flag | If ANY code in the episode has a cross-use flag, the episode gets that flag. Priority: most specific flag wins. Matches the treatment_line F>S>E>N aggregation pattern. | ✓ |
| Parallel list | Semicolon-separated like medication_name. Shows per-code flags at episode level. Consistent with other multi-value columns. | |
| You decide | Claude picks based on the actual flag values found in the xlsx and what makes clinical sense for Phase 93's temporal logic. | |

**User's choice:** Any-positive flag (Recommended)
**Notes:** Most specific flag wins. Mirrors the treatment_line aggregation approach.

---

## Claude's Discretion

- Cross-use flag normalization strategy (inspect xlsx column 9 values, then decide)
- Exact column indices for sheets with fewer than 9 columns
- Pre-join deduplication logic
- TBD xlsx export filename and location
- Whether to version-stamp xlsx reference file in data/reference/

## Deferred Ideas

None — discussion stayed within phase scope
