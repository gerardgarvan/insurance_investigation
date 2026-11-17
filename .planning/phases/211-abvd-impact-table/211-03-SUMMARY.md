# 211-03 SUMMARY — COMPLETE (probe + reconciliation recorded; sheet code deferred)

## Task 0 probe (HiPerGator, 2026-11-17, pasted by user)
- File: `output/gantt_episodes_180_flags_20261117.csv` (R/209; built from the pre-210 32-col Gantt). 22,548 rows, 38 cols.
- No `.planning/schemas/211_schema_*.md` was written, so column names are not in a probe file. Only counts were pasted.

## Reconciliation (authoritative, patient level)
| Measure | R/209 (pre-210 Gantt) | Phase 210 (new Gantt) | Diff |
|---|---|---|---|
| ever_abvd (pipeline) | 1,244 | 1,169 (episode-derived) | -75 |
| ever_abvd_plus | 163 | n/a (deprecated flag) | |
| ever_abvd_episode (R/209) | 1,052 | 1,169 (Phase 210 ever_abvd) | +117 |
| ever_abvd_plus_episode (R/209) | 163 | | |
| ever_brentuximab | 954 | | |
| ever_brentuximab_episode | 776 | | |

- ever_abvd TRUE / episode FALSE: 192 patients.
- ever_brentuximab TRUE / episode FALSE: 178 = R/142 D-02b raw-only count (brentuximab found only in raw MED_ADMIN / PRESCRIBING / PROCEDURES, not in Gantt drug text).
- 192 + 1,052 = 1,244 (consistent). 178 + 776 = 954 (consistent).
- Phase 210 vs R/209 episode-derived difference (1,169 vs 1,052) reflects the 210 rule (flag from episode drugs, ABVD-01); not further decomposed here.

## `reconciliation` sheet spec (for R/211, not yet coded)
- Sheet `reconciliation`, after `ever_abvd_x_avd`; KEY lists it.
- Rows: the six R/209 measures above, the two crosstab rows (192, 178), each beside the Phase 210 value read from the new CSV, with a difference column; counts 1-10 shown `<11`.
- Input pinned: `R211_R209_CSV` default `output/gantt_episodes_180_flags_20261117.csv`; KEY records path + pinned TRUE/FALSE; stop if missing.
- R/209 values read at run time by exact column name, one match or stop (print available names). Column names must come from a schema probe file; run `probe_inputs("211", files = "output/gantt_episodes_180_flags_20261117.csv")` on HiPerGator first. No numbers typed in code.
- Notes: measured wording, no causal claims.

## Deviations
- Roadmap criterion 2 says "read by exact label from R/209 output"; the R/209 output is a patient/episode CSV (38 cols), so values are read by column + any() / n_distinct, not by row label.
- Sheet code not written: blocked on column names (CLAUDE.md probe rule). Carry to a follow-up quick task.

## Assumptions (headless run)
- User-pasted numbers treated as authoritative; no rerun.
- Phase marked complete per user instruction; sheet code deferred.
