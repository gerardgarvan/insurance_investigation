# Schema probe: 188_dated_events (2026-10-22)
Names, types and counts only. Counts 1-10 shown as <11. No patient-level values.

Probed by user on HiPerGator 2026-10-22 during Phase 188 planning.

## /blue/erin.mobley-hl.bcu/clean/rds/outputs/survivorship_dated_events_20261012.rds
rows: 1,054,151 | cols: 3
distinct ID: 8,623

- `ID` <character> (identifier/sensitive: values not shown)
- `modality` <character> levels (descending count):
  - KIDNEY: 231,234
  - BMP: 222,732
  - Complete blood count: 177,515
  - LFT: 174,949
  - CMP: 161,944
  - Electrocardiogram: 25,157
  - Thyroid function: 24,020
  - LIPID: 14,405
  - Echocardiogram: 12,026
  - Pulmonary function test: 5,029
  - Mammogram: 2,928
  - Stress test: 1,247
  - Multiple gated acquisition (MUGA): 517
  - Breast MRI: 448
- `event_date` <Date> range=[2012-01-02, 2025-03-29]

## D-02a Window Check
No `window`, `tier`, or `year_index` column present.
File is NOT windowed — contains all surveillance event dates per patient across the full follow-up period.
Implication: `n_echoes_before_or_on_last_dose` in Phase 188 is a full count, not limited to a survivorship window. KEY states this.

## Echo filter
`modality == "Echocardiogram"` — exact string confirmed from this probe.
