# =============================================================================
# Phase 143-02 Checkpoint: HiPerGator verification (Steps 1-7)
# Run in RStudio on HiPerGator after pulling latest main.
# =============================================================================

source("R/00_config.R")

# ---------------------------------------------------------------------------
# Step 1: Archive current enriched file (safe if already archived)
# ---------------------------------------------------------------------------
pre143_snapshot <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes_enriched_pre143.rds")
if (!file.exists(pre143_snapshot)) {
  file.copy(
    file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"),
    pre143_snapshot,
    overwrite = FALSE
  )
  message("Step 1: Snapshot saved to treatment_episodes_enriched_pre143.rds")
} else {
  message("Step 1: Snapshot already exists - skipping copy")
}

# ---------------------------------------------------------------------------
# Step 2: Idempotency probe - check for double-run corruption
# ---------------------------------------------------------------------------
ep_current <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
if (any(grepl("\\.x$|\\.y$", names(ep_current)))) {
  stop("Step 2 FAIL: .x/.y suffixed columns found - prior double-run corrupted the RDS")
}
enrich_cols <- c("drug_group", "code_type", "source_table",
                 "episode_dx_codes", "episode_dx_categories", "episode_dx_7day_confirmed")
cat(sprintf("Step 2: enrichment columns already present: %d of 6\n",
            sum(enrich_cols %in% names(ep_current))))
cat("Step 2: columns in current RDS:\n")
cat(paste(names(ep_current), collapse = ", "), "\n\n")
rm(ep_current)

# ---------------------------------------------------------------------------
# Step 3: Regenerate unenriched input, then run R/28 with 90-day defaults
# ---------------------------------------------------------------------------
message("Step 3: Running R/26 (unenriched episodes)...")
source("R/26_treatment_episodes.R")

message("Step 3: Running R/28 (90-day defaults, no suffix)...")
source("R/28_episode_classification.R")

# ---------------------------------------------------------------------------
# Step 4: Object equality - 90-day output must be unchanged
# ---------------------------------------------------------------------------
a <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
b <- readRDS(pre143_snapshot)
cmp <- all.equal(a, b)
if (!isTRUE(cmp)) {
  print(cmp)
  stop("Step 4 FAIL: 90-day enrichment output changed - halt and investigate")
}
cat("Step 4: PASS - 90-day enriched output unchanged\n\n")

# ---------------------------------------------------------------------------
# Step 5: Run R/28 for 180-day path
# ---------------------------------------------------------------------------
message("Step 5: Running R/28 for 180-day enrichment (out_suffix = '_180_enriched')...")
old_opts <- options(
  p143_episodes_rds = file.path(CONFIG$cache$outputs_dir, "treatment_episodes_180.rds"),
  p143_detail_rds   = file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail_180.rds"),
  p143_out_suffix   = "_180_enriched"
)
on.exit(options(old_opts), add = TRUE)
source("R/28_episode_classification.R")
options(old_opts)

enriched_180_path <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes_180_enriched.rds")
if (!file.exists(enriched_180_path)) {
  stop("Step 5 FAIL: treatment_episodes_180_enriched.rds was not created")
}
message("Step 5: treatment_episodes_180_enriched.rds created\n")

# ---------------------------------------------------------------------------
# Step 6: Fill-rate comparison against 90-day benchmarks
# ---------------------------------------------------------------------------
benchmarks <- c(
  drug_group                = 40.2,
  code_type                 = 67.2,
  source_table              = 67.2,
  episode_dx_codes          = 61.5,
  episode_dx_categories     = 61.5,
  episode_dx_7day_confirmed = 61.2
)

ep_enriched <- readRDS(enriched_180_path)
fill180 <- vapply(names(benchmarks),
                  function(col) mean(!is.na(ep_enriched[[col]]) & trimws(ep_enriched[[col]]) != ""),
                  numeric(1))

cmp_table <- data.frame(
  column    = names(benchmarks),
  fill_90   = benchmarks,
  fill_180  = round(100 * fill180, 1),
  row.names = NULL
)
cmp_table$delta <- cmp_table$fill_180 - cmp_table$fill_90
cat("Step 6: Fill-rate comparison (90-day benchmark vs 180-day enriched):\n")
print(cmp_table)

if (any(fill180 == 0)) {
  stop("Step 6 FAIL: one or more enrichment columns are 0% - enrichment did not apply")
}
cat("Step 6: PASS - all six enrichment columns populated in 180-day file\n\n")

# ---------------------------------------------------------------------------
# Step 7: Smoke test
# ---------------------------------------------------------------------------
message("Step 7: Running R/88_smoke_test_comprehensive.R...")
source("R/88_smoke_test_comprehensive.R")
