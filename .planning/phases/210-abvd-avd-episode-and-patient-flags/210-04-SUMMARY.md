# 210-04 Summary — HiPerGator run of R/142 and R/206

**Status: COMPLETE (HiPerGator run succeeded 2026-11-17)**

## Local pre-flight (done 2026-11-17)
- `tools/rcheck.sh parse` on R/00_config.R, R/utils/utils_abvd_flags.R, R/142_gantt_180_export.R, R/206_apply_decisions_gantt180.R, tests/testthat/test-210-abvd-avd-flags.R: 5 parsed, 0 failed.
- `tools/rcheck.sh test 210`: 0 failed, 0 errors. `test 201`: 0 failed, 0 errors. (Only warning: reference Excel absent locally.)

## Adjustment vs plan 04 (headless run)
- Pre-run backup is timestamped and never skipped silently: `output/internal/gantt_episodes_180_pre210_<YYYYmmdd_HHMMSS>.csv`. Step 2 below stops if the source is missing or the copy fails.
- Phase 211 pins the backup path printed by step 2.

## HiPerGator console steps
Sync plans 01-03 first (edit locally -> sync). Then:
```
module load R/4.5
R --no-save
```
In R, from the repo root:
```r
# 1. Timestamped backup of the delivered file (stops loudly, never skips)
src <- "output/gantt_episodes_180.csv"
stopifnot("source gantt_episodes_180.csv missing" = file.exists(src))
dir.create("output/internal", showWarnings = FALSE, recursive = TRUE)
bak <- file.path("output/internal", paste0("gantt_episodes_180_pre210_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv"))
stopifnot("backup target already exists" = !file.exists(bak))
ok <- file.copy(src, bak, overwrite = FALSE)
stopifnot("backup copy failed" = isTRUE(ok), "backup size mismatch" = file.size(bak) == file.size(src))
cat("PRE210 BACKUP:", bak, "\n")

# 2. R/142
source("R/142_gantt_180_export.R", local = new.env(parent = globalenv()))

# 3. R/206
source("R/206_apply_decisions_gantt180.R", local = new.env(parent = globalenv()))

# 4. Compact check (counts only, 1-10 shown as <11)
g <- read.csv("output/gantt_episodes_180.csv", colClasses = "character", na.strings = "")
fs <- function(n) if (n >= 1 && n <= 10) "<11" else format(n, big.mark = ",")
cat(nrow(g), "rows;", ncol(g), "cols;", paste(names(g)[31:ncol(g)], collapse = ", "), "\n")
ch <- !is.na(g$treatment_type) & g$treatment_type == "Chemotherapy"
tb <- table(abvd = g$abvd_episode[ch], avd = g$avd_episode[ch])
for (i in rownames(tb)) for (j in colnames(tb)) cat("abvd_episode", i, "avd_episode", j, fs(tb[i, j]), "\n")
pts <- function(cn) unique(g$patient_id[g[[cn]] == "TRUE"])
for (cn in c("ever_abvd", "ever_avd", "ever_abvd_plus")) cat(cn, fs(length(pts(cn))), "\n")
cat("ever_abvd & ever_avd", fs(length(intersect(pts("ever_abvd"), pts("ever_avd")))), "\n")
d <- "output/gantt_episodes_180_flag_dictionary.csv"
cat("dictionary:", file.exists(d), "\n")
if (file.exists(d)) print(read.csv(d, stringsAsFactors = FALSE)[grepl("^qc:", read.csv(d, stringsAsFactors = FALSE)$column), c("column", "definition")])
cat("pre210 copy:", file.exists(bak), "\n")
```
## Paste back
- After R/142: `AVD_INCLUDES_BV_NIVO = ...`, the "Phase 210 flags" QC lines (incl. `JCODE_ABVD fallback episodes ...`), `Schema verification:` line. On error: error + ~20 lines above.
- After R/206: all `OK:` lines, ever_abvd / ever_avd / both / episode-count lines, JCODE_ABVD fallback line, final `wrote ... (34 columns, ...)` line. On error: error + ~20 lines.
- Step 4: all printed lines, plus the `PRE210 BACKUP:` line.
- Expected: 34 cols ending `abvd_class, ever_abvd_plus, avd_episode, ever_avd`; no `abvd_episode TRUE avd_episode TRUE` cell; dictionary and backup TRUE.
- Also check whether `triggering_codes` carries J-codes on chemo rows (fallback count shows how far J-code evidence reaches); unverified locally.

## Results (HiPerGator, 2026-11-17, pasted by Gerard)
- R/142: schema PASSED, 34 cols.
- R/206: all QC `OK`; 22,548 rows.
- abvd_episode TRUE: 1,254 episodes (ABVD 1,125 + ABVD_PLUS 129).
- avd_episode TRUE: 570 episodes (AVD 236 + BV+AVD 255 + Nivo+AVD 42 + ABVD_PLUS 37).
- abvd_episode x avd_episode TRUE/TRUE: 0 (assertion holds).
- Patients: ever_abvd 1,169 (before 1,230); ever_avd 520; both 51; ever_abvd_plus 163 (deprecated).
- JCODE_ABVD fallback episodes: 0.
- Base -> new abvd_episode: FALSE->TRUE 145; TRUE->FALSE 236.
- Backup: `output/internal/gantt_episodes_180_pre210_20261117_120409.csv` (Phase 211 pins this path).

## Assumptions (headless run)
- Results transcribed from Gerard's message; not re-verified locally (data on HiPerGator).
