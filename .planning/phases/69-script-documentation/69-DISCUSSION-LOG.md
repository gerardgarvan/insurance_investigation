# Phase 69: Script Documentation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 69-script-documentation
**Areas discussed:** Header block template, Section header format, WHY comment depth, Script scope & batching

---

## Header Block Template

### Q1: What fields should every script header include?

| Option | Description | Selected |
|--------|-------------|----------|
| Standard 5-field | Purpose, Inputs, Outputs, Dependencies, Requirements. Matches best existing headers. | ✓ |
| Extended 7-field | Standard 5 plus Phase/milestone created, Last modified date. More traceability but harder to keep updated. | |
| Minimal 3-field | Purpose, Inputs, Outputs only. Lean but may miss dependency chain info. | |

**User's choice:** Standard 5-field (Recommended)
**Notes:** None

### Q2: How should the header be visually delimited?

| Option | Description | Selected |
|--------|-------------|----------|
| Box style with equals | Match existing `# ============` top/bottom borders. Already used by ~90% of scripts. | ✓ |
| Roxygen2 style #' | Use #' prefix for all header lines. Consistent with utils/ but different from pipeline convention. | |
| You decide | Claude picks the format that best fits existing patterns. | |

**User's choice:** Box style with equals (Recommended)
**Notes:** None

---

## Section Header Format

### Q3: What section header format should be the standard?

| Option | Description | Selected |
|--------|-------------|----------|
| # SECTION N: TITLE ---- | Numbered sections with 4+ trailing dashes. Works with RStudio Ctrl+Shift+O. | ✓ |
| # Title ---- | Unnumbered section headers. Simpler but loses ordering cues. | |
| # ---- Title ---- | Centered dashes. Visually distinct but some RStudio versions may not parse. | |

**User's choice:** # SECTION N: TITLE ---- (Recommended)
**Notes:** None

### Q4: Should scripts have a consistent section ordering?

| Option | Description | Selected |
|--------|-------------|----------|
| Flexible per script | Each script can have domain-appropriate sections. Only require Setup and Output sections. | ✓ |
| Strict template | Every script must have: Setup, Load Data, Process, Validate, Output. May feel forced. | |
| You decide | Claude decides the section structure per script. | |

**User's choice:** Flexible per script (Recommended)
**Notes:** None

---

## WHY Comment Depth

### Q5: How deep should WHY comments go?

| Option | Description | Selected |
|--------|-------------|----------|
| Clinical + business rules only | Comment WHY for clinical rules, payer hierarchy, magic numbers, complex joins. Skip obvious dplyr. | ✓ |
| Comprehensive | Comment every non-trivial operation. Maximizes onboarding but risks over-commenting. | |
| Minimal | Only comment truly obscure logic. Assumes reader knows R/tidyverse. | |

**User's choice:** Clinical + business rules only (Recommended)
**Notes:** None

### Q6: Should decision traceability (D-01, D-02 references) be preserved or removed?

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve existing | Keep D-xx references where they exist. Don't add new ones. | ✓ |
| Add more | Add D-xx or REQ-xx references throughout. Full traceability. | |
| Remove all | Remove D-xx references -- internal planning artifacts. | |

**User's choice:** Preserve existing (Recommended)
**Notes:** None

---

## Script Scope & Batching

### Q7: How should the documentation work be batched across plans?

| Option | Description | Selected |
|--------|-------------|----------|
| By decade | One plan per decade grouping. Natural grouping, parallelizable, manageable scope. | ✓ |
| By effort level | Plan 1: header standardization. Plan 2: section headers. Plan 3: WHY comments. Risks triple-touching files. | |
| All at once | One giant plan. Simple but huge context and high failure risk. | |

**User's choice:** By decade (Recommended)
**Notes:** None

### Q8: Should R/utils/ scripts be included in this phase?

| Option | Description | Selected |
|--------|-------------|----------|
| Standardize headers only | Utils already have good roxygen2 docs. Just standardize header blocks. | ✓ |
| Full treatment | Add section headers and WHY comments to utils too. | |
| Exclude utils entirely | Phase 69 targets only the 67 numbered pipeline scripts. | |

**User's choice:** Standardize headers only (Recommended)
**Notes:** None

---

## Claude's Discretion

- Exact wording of header fields and section titles per script
- How many sections each script warrants
- Which specific lines warrant WHY comments
- Wave grouping and parallelization of decade-based plans

## Deferred Ideas

None -- discussion stayed within phase scope
