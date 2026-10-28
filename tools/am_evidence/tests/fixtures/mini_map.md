---
phase: 190-evidence-map
plan: 01
created: 2026-10-27
status: DRAFT
---

# AM Evidence Map — Mini Fixture

---

## ID Registry

| ID | Created | First Row | Notes |
|----|---------|-----------|-------|
| S1-LOG-01 | 2026-10-27 | S1 ingest table | §1 Data Ingest table |
| S3-DEC-01 | 2026-10-27 | S3 decision log | §3 Decision Log |
| S4-DXDT-01 | 2026-10-27 | S4 DXDT expected | §4 Cancer Diagnosis Date — Expected Structure |
| S4-CBC-01 | 2026-10-27 | S4-CBC repo | REPO-ONLY: CBC definition |
| S4-SHS-01 | 2026-10-27 | S4-SHS repo | REPO-ONLY: Single-health-system flag |
| S8-PRK-01 | 2026-10-27 | S8 parking | §8 Open Questions |
| SA1-LOG-01 | 2026-10-27 | SA1 ingest | Appendix A1 Data Ingest |
| SA3-DEC-01 | 2026-10-27 | SA3 decision | Appendix A3 Decision Log |
| D-191-01 | 2026-10-28 | AM-MAP-03 | Claims secondary source |
| DEC-001 | 2026-10-27 | AM-MAP-03 | D-190-01 |

---

## Main Map

| ID | Origin | AM Section | Domain | Item | Manual Lines | Manual Text | Status | Evidence Type | Repo Source | What the Source Shows | Lead | Decision ID | Notes |
|----|--------|------------|--------|------|--------------|-------------|--------|---------------|-------------|----------------------|------|-------------|-------|
| S1-LOG-01 | MANUAL | §1 Data Ingest & Change Log | LOG | Ingest events | L1 | Data Ingest table | EMPTY-REPO-CAN-ANSWER | CODE | R/00_config.R | Config shows ingest paths | — | — | — |
| S3-DEC-01 | MANUAL | §3 Variable and Phenotype Decision Log | DEC | Decision log | L3 | Decision log table | EMPTY-REPO-CAN-ANSWER | TEAM-DECISION | AM-MAP-03 | Confirmed decisions | — | — | — |
| S4-DXDT-01 | MANUAL | §4 Data Cleaning and Harmonization Rules | DXDT | Expected Structure | L5 | Expected fields | FILLED-NEEDS-CHECK | CODE | R/00_config.R:CANCER_CODES | Code shows ICD codes | — | — | — |
| S8-PRK-01 | MANUAL | §8 Open Questions and Decision Parking Lot | PRK | Parking lot | L7 | Open questions | EMPTY-REPO-CAN-ANSWER | NONE | — | — | — | — | — |
| SA1-LOG-01 | MANUAL | Appendix A1 | LOG | A1 ingest mirror | L9 | Mirror of §1 | EMPTY-REPO-CAN-ANSWER | CODE | R/00_config.R | Config shows ingest paths | — | — | — |
| SA3-DEC-01 | MANUAL | Appendix A3 | DEC | A3 decision mirror | L11 | Mirror of §3 | EMPTY-REPO-CAN-ANSWER | TEAM-DECISION | AM-MAP-03 | Confirmed decisions | — | — | — |

---

## AM-MAP-02: Repo Domains Not in Manual

| ID | Origin | AM Section | Domain | Item | Manual Lines | Manual Text | Status | Evidence Type | Repo Source | What the Source Shows | Lead | Decision ID | Notes |
|----|--------|------------|--------|------|--------------|-------------|--------|---------------|-------------|----------------------|------|-------------|-------|
| S4-CBC-01 | REPO-ONLY | §4 Data Cleaning and Harmonization Rules | CBC | CBC definition | — | — | EMPTY-REPO-CAN-ANSWER | CODE | R/utils/utils_distance_cbc.R:build_cbc_events() | Defines CBC events | — | — | — |
| S4-SHS-01 | REPO-ONLY | §4 Data Cleaning and Harmonization Rules | SHS | Single-health-system flag | — | — | EMPTY-REPO-CAN-ANSWER | CODE | R/169_single_source_care.R | SHS flag logic | — | — | — |

---

## AM-MAP-03: Team Decisions

| Decision ID | Original ID | Decision Text | Raised By | Decided By | Date | Source File | Map Row(s) | Status | Notes |
|-------------|-------------|---------------|-----------|------------|------|-------------|------------|--------|-------|
| DEC-001 | — | OneFLquestions document location unknown | Gerard | — | 2026-10-27 | STATE.md | S8-PRK-01 | OPEN | Proceed without it |
| D-191-01 | — | Claims secondary source not in pipeline | Gerard | — | 2026-10-28 | AM-VERDICTS.md | S4-DXDT-01 | OPEN | Dataset loading only |

---

## Coverage

| Line Reference | Reason | Notes |
|---------------|--------|-------|
| L2 | header | — |
| L4 | header | — |
| L6 | header | — |
| L8 | header | — |
| L10 | header | — |
| L12 | header | — |
