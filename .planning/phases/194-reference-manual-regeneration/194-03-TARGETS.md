# Phase 194 Plan 03 — Target List

**Date:** 2026-11-05
**Approach:** (a) — teach R/89 to read the dominant existing format.

All utils modules are already PARSEABLE (five-field banner). No utils edits needed.
All two-digit production scripts (00–69) are PARSEABLE. No edits needed.
Three-digit scripts in R/39 that are PARSEABLE are already parseable. No edits needed.

Target = all production scripts classed USABLE (7 scripts). These lack the
`# ==...==` opening banner on the first line, or lack the five labelled fields
inside a banner, so `parse_script_header()` returns "Not documented."

| file | audit class | reason for edit |
|---|---|---|
| R/120_zip5_backfill_concordance.R | USABLE | Inline prose header, no `# ===` banner; needs banner + five-field block prepended |
| R/121_zip_problem_inventory.R | USABLE | Inline prose header, no `# ===` banner; needs banner + five-field block prepended |
| R/162_export_patient_modality_dates.R | USABLE | Has `# ===` banner but spec fields absent (has "Usage:" not "Purpose:"); convert to spec |
| R/169_single_source_care.R | USABLE | Opening `# R/169...` prose line precedes the banner; parser finds banner as first `===` but Phase/Plan annotations dilute field extraction; reformat to spec |
| R/170_nhl_gantt_subsets.R | USABLE | Same pattern as R/169 |
| R/186_survivorship_rate_granularity.R | USABLE | Has `# ===` banners but as section markers with no five-field block; needs spec header inserted |
| R/187_anthracycline_exposure.R | USABLE | Has Inputs/Outputs prose before `# ===` SECTION 0 banner; no opening banner; needs spec header |
| R/188_echo_rate_since_anthracycline.R | USABLE | Has schema prose but no banner and no Purpose/Inputs/Outputs labels; needs spec header |
