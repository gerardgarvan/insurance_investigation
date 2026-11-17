# 211-04 SUMMARY — PENDING HIPERGATOR (incomplete)

## PENDING HIPERGATOR

```
module load R/4.5
R --no-save
```
```r
bak <- "output/internal/gantt_episodes_180_pre210_20261117_120409.csv"
stopifnot(file.exists(bak), file.exists("output/gantt_episodes_180.csv"))
cat(length(names(read.csv(bak, nrows = 1))), "old cols\n")
cat(length(names(read.csv("output/gantt_episodes_180.csv", nrows = 1))), "new cols\n")
source("R/211_abvd_impact_table.R", local = new.env(parent = globalenv()))
```
Paste back: both column counts and all R/211 console checkpoint lines (row counts, alignment check, sheets, output path). On error: the error plus ~20 lines.
Close-out: copy `output/211_abvd_impact_<RUN_DATE>.xlsx` unchanged into this phase folder; record counts against 211-CONTEXT.md.

## Assumptions (headless run)
- Run is without the 211-03 reconciliation sheet (pending probe).
