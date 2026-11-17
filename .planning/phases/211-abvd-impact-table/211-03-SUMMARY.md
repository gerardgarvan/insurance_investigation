# 211-03 SUMMARY — PENDING HIPERGATOR (incomplete)

- Task 0 (probe R/209 output) needs HiPerGator. Task 1 (reconciliation sheet) is blocked on it. Not started.
- R/209 is not in the repo; not created.

## PENDING HIPERGATOR

```
module load R/4.5
R --no-save
```
```r
f <- list.files("output", pattern = "209", full.names = TRUE)   # discovery only, never for pinning
print(f)
probe_inputs("211", files = c("<path>"))   # writes .planning/schemas/211_schema_*.md
```
Paste back: printed file names, plus the probe file's sheet and first-column label lines.

## Assumptions (headless run)
- Plan left incomplete; plan 04 does not depend on the reconciliation sheet to run R/211 (sheets from 211-02), so it can run first, and the reconciliation sheet is added after the probe.
