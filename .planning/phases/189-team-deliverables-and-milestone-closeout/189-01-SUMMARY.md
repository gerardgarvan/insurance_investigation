---
phase: 189-team-deliverables-and-milestone-closeout
plan: "01"
subsystem: team-communications
tags: [nhl, explainer, comm-01, clinical-document, suppression]
dependency_graph:
  requires:
    - 168-01 (nhl_only_episodes_20261008.csv, hl_nhl_episodes_20261008.csv)
  provides:
    - output/189-NHL-EXPLAINER-20261023.md
    - .planning/phases/189-team-deliverables-and-milestone-closeout/189-NHL-EXPLAINER-20261023.md
  affects: []
tech_stack:
  added: []
  patterns:
    - pinned-env-var input paths with dated defaults
    - suppress_n() for HIPAA count suppression
    - byte-for-byte copy verification (readLines identity check)
key_files:
  created:
    - R/189_nhl_explainer.R
    - output/189-NHL-EXPLAINER-20261023.md
    - .planning/phases/189-team-deliverables-and-milestone-closeout/189-NHL-EXPLAINER-20261023.md
  modified: []
decisions:
  - "Patient counts read at runtime from pinned R/170 CSV outputs; no hardcoded values in script"
  - "suppress_n() applied to all counts; both subsets suppressed together if either < 11"
  - "Classification wording tied to R/170 classify_patient_groups() logic (lines cited in script comments)"
metrics:
  duration_minutes: 30
  tasks_completed: 2
  files_changed: 3
  completed_date: "2026-10-23"
requirements_met: [COMM-01]
---

# Phase 189 Plan 01: NHL Explainer Document Summary

**One-liner:** Script-generated NHL subset explainer (COMM-01) for clinical team — reads counts from pinned R/170 outputs at runtime, suppresses per HIPAA, cites all required data sources in the analyst footnote.

## What Was Built

`R/189_nhl_explainer.R` generates a clinical-language explainer document for Amy, Erin, and Sharon explaining how patients were assigned to the NHL-only and HL+NHL subsets.

The script:
- Pins the two R/170 output CSVs via env vars `R189_NHL_ONLY` and `R189_HL_NHL` (dated defaults: `output/internal/nhl_only_episodes_20261008.csv` and `output/internal/hl_nhl_episodes_20261008.csv`)
- Reads distinct `patient_id` values from each CSV, counts overlap, and stops if overlap > 0
- Applies `suppress_n()` to all counts (0 → "0"; 1–10 → "<11"; ≥11 → as-is); both subsets suppressed together if either falls below 11
- Writes prose paragraphs followed by a compact summary table to `output/189-NHL-EXPLAINER-<YYYYMMDD>.md`
- Copies unchanged to the phase folder with a byte-for-byte identity check

**HiPerGator run (2026-10-23):**
```
[R/189] NHL-only: 849 | HL+NHL: 176 | overlap: 0
[R/189] Explainer written: .../output/189-NHL-EXPLAINER-20261023.md
[R/189] Phase copy written: .../.planning/phases/189-team-deliverables-and-milestone-closeout/189-NHL-EXPLAINER-20261023.md
```

**Output file:** `output/189-NHL-EXPLAINER-20261023.md` and phase folder copy (identical).

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — counts are wired to real R/170 outputs confirmed by HiPerGator run.

## Self-Check: PASSED

- R/189_nhl_explainer.R: present (commit 212ba25)
- output/189-NHL-EXPLAINER-20261023.md: confirmed by HiPerGator run
- .planning/phases/189-team-deliverables-and-milestone-closeout/189-NHL-EXPLAINER-20261023.md: present (pulled to Windows repo)
- No hardcoded counts: `grep -E "849|176" R/189_nhl_explainer.R` returns nothing
- All required citations present: gantt_episodes_180.csv, Chemo_combos_6mo_amc090826-smc, "Chemo and Cancer Dx", all six column names E–J
- No causal language: grep for significant/caused by/leads to/results in returns nothing
- Console overlap = 0 matches plan design
