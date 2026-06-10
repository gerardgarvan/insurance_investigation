# ==============================================================================
# 95_validate_dt_infrastructure.R -- Phase 95 infrastructure validation
# ==============================================================================
#
# Purpose:
#   One-time validation script confirming data.table infrastructure is correctly
#   installed and all LOOKUP_TABLES_DT entries are keyed and contain expected data.
#   Run after Phase 95 implementation to verify INFRA-01 through INFRA-04.
#
# Usage:
#   source("R/95_validate_dt_infrastructure.R")
#
# Expected output:
#   Series of [PASS] / [FAIL] messages. All must show [PASS].
#
# Requirements:
#   - INFRA-01: data.table 1.18.4+ installed
#   - INFRA-02: utils_dt.R functions available
#   - INFRA-03: LOOKUP_TABLES_DT has 6 keyed data.tables
#   - INFRA-04: Zero behavior change (existing objects intact)
#
# ==============================================================================

source("R/00_config.R")

pass_count <- 0L
fail_count <- 0L

check <- function(description, condition) {
  if (isTRUE(condition)) {
    message(sprintf("[PASS] %s", description))
    pass_count <<- pass_count + 1L
  } else {
    message(sprintf("[FAIL] %s", description))
    fail_count <<- fail_count + 1L
  }
}

# ==============================================================================
# Section 1: INFRA-01 checks (data.table installation)
# ==============================================================================

check("data.table is installed", requireNamespace("data.table", quietly = TRUE))
check("data.table version >= 1.18.4", packageVersion("data.table") >= "1.18.4")
check("data.table is loaded (library call in 00_config.R)", "data.table" %in% .packages())

# ==============================================================================
# Section 2: INFRA-02 checks (utils_dt.R functions)
# ==============================================================================

# Function existence checks
check("ensure_dt() exists", exists("ensure_dt") && is.function(ensure_dt))
check("to_tibble_safe() exists", exists("to_tibble_safe") && is.function(to_tibble_safe))
check("get_lookup_dt() exists", exists("get_lookup_dt") && is.function(get_lookup_dt))

# ensure_dt() behavior checks
check(
  "ensure_dt() converts tibble to data.table",
  data.table::is.data.table(ensure_dt(tibble::tibble(x = 1:3)))
)
check(
  "ensure_dt() no-op on data.table",
  data.table::is.data.table(ensure_dt(data.table::data.table(x = 1:3)))
)
check(
  "ensure_dt() errors on NULL",
  tryCatch({ensure_dt(NULL); FALSE}, error = function(e) TRUE)
)
check(
  "ensure_dt() warns on empty",
  length(tryCatch(
    {ensure_dt(tibble::tibble(x = integer(0))); character(0)},
    warning = function(w) w
  )) > 0
)

# to_tibble_safe() behavior checks
check(
  "to_tibble_safe() converts data.table to tibble",
  tibble::is_tibble(to_tibble_safe(data.table::data.table(x = 1:3)))
)
check(
  "to_tibble_safe() errors on NULL",
  tryCatch({to_tibble_safe(NULL); FALSE}, error = function(e) TRUE)
)

# get_lookup_dt() behavior checks
check(
  "get_lookup_dt() retrieves AMC_PAYER_LOOKUP",
  data.table::is.data.table(get_lookup_dt("AMC_PAYER_LOOKUP"))
)
check(
  "get_lookup_dt() errors on bad name",
  tryCatch({get_lookup_dt("NONEXISTENT"); FALSE}, error = function(e) TRUE)
)

# ==============================================================================
# Section 3: INFRA-03 checks (LOOKUP_TABLES_DT structure)
# ==============================================================================

check("LOOKUP_TABLES_DT exists", exists("LOOKUP_TABLES_DT") && is.list(LOOKUP_TABLES_DT))
check("LOOKUP_TABLES_DT has 6 entries", length(LOOKUP_TABLES_DT) == 6)
check(
  "All 6 names present",
  all(c("AMC_PAYER_LOOKUP", "DRUG_GROUPINGS", "CODE_SUBCATEGORY_MAP",
        "CANCER_SITE_MAP", "TIER_MAPPING", "TREATMENT_CODES") %in% names(LOOKUP_TABLES_DT))
)

# --- AMC_PAYER_LOOKUP checks ---
check(
  "AMC_PAYER_LOOKUP is data.table",
  data.table::is.data.table(LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP)
)
check(
  "AMC_PAYER_LOOKUP has key",
  length(data.table::key(LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP)) > 0
)
check(
  "AMC_PAYER_LOOKUP cols: code, payer_category",
  all(c("code", "payer_category") %in% names(LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP))
)
check(
  "AMC_PAYER_LOOKUP row count matches named vector",
  nrow(LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP) == length(AMC_PAYER_LOOKUP)
)

# --- DRUG_GROUPINGS checks ---
check(
  "DRUG_GROUPINGS is data.table",
  data.table::is.data.table(LOOKUP_TABLES_DT$DRUG_GROUPINGS)
)
check(
  "DRUG_GROUPINGS has key",
  length(data.table::key(LOOKUP_TABLES_DT$DRUG_GROUPINGS)) > 0
)
check(
  "DRUG_GROUPINGS cols: code, drug_group",
  all(c("code", "drug_group") %in% names(LOOKUP_TABLES_DT$DRUG_GROUPINGS))
)
check(
  "DRUG_GROUPINGS row count matches named vector",
  nrow(LOOKUP_TABLES_DT$DRUG_GROUPINGS) == length(DRUG_GROUPINGS)
)

# --- CODE_SUBCATEGORY_MAP checks ---
check(
  "CODE_SUBCATEGORY_MAP is data.table",
  data.table::is.data.table(LOOKUP_TABLES_DT$CODE_SUBCATEGORY_MAP)
)
check(
  "CODE_SUBCATEGORY_MAP has key",
  length(data.table::key(LOOKUP_TABLES_DT$CODE_SUBCATEGORY_MAP)) > 0
)
check(
  "CODE_SUBCATEGORY_MAP cols: code, subcategory",
  all(c("code", "subcategory") %in% names(LOOKUP_TABLES_DT$CODE_SUBCATEGORY_MAP))
)
check(
  "CODE_SUBCATEGORY_MAP row count matches named vector",
  nrow(LOOKUP_TABLES_DT$CODE_SUBCATEGORY_MAP) == length(CODE_SUBCATEGORY_MAP)
)

# --- CANCER_SITE_MAP checks ---
check(
  "CANCER_SITE_MAP is data.table",
  data.table::is.data.table(LOOKUP_TABLES_DT$CANCER_SITE_MAP)
)
check(
  "CANCER_SITE_MAP has key",
  length(data.table::key(LOOKUP_TABLES_DT$CANCER_SITE_MAP)) > 0
)
check(
  "CANCER_SITE_MAP cols: prefix, cancer_site",
  all(c("prefix", "cancer_site") %in% names(LOOKUP_TABLES_DT$CANCER_SITE_MAP))
)
check(
  "CANCER_SITE_MAP row count matches named vector",
  nrow(LOOKUP_TABLES_DT$CANCER_SITE_MAP) == length(CANCER_SITE_MAP)
)

# --- TIER_MAPPING checks ---
check(
  "TIER_MAPPING is data.table",
  data.table::is.data.table(LOOKUP_TABLES_DT$TIER_MAPPING)
)
check(
  "TIER_MAPPING has key",
  length(data.table::key(LOOKUP_TABLES_DT$TIER_MAPPING)) > 0
)
check(
  "TIER_MAPPING cols: payer_category, tier",
  all(c("payer_category", "tier") %in% names(LOOKUP_TABLES_DT$TIER_MAPPING))
)
check(
  "TIER_MAPPING row count matches list",
  nrow(LOOKUP_TABLES_DT$TIER_MAPPING) == length(TIER_MAPPING)
)

# --- TREATMENT_CODES checks ---
check(
  "TREATMENT_CODES is data.table",
  data.table::is.data.table(LOOKUP_TABLES_DT$TREATMENT_CODES)
)
check(
  "TREATMENT_CODES has key",
  length(data.table::key(LOOKUP_TABLES_DT$TREATMENT_CODES)) > 0
)
check(
  "TREATMENT_CODES cols: code, code_system, treatment_type",
  all(c("code", "code_system", "treatment_type") %in% names(LOOKUP_TABLES_DT$TREATMENT_CODES))
)
check(
  "TREATMENT_CODES has rows (flattened)",
  nrow(LOOKUP_TABLES_DT$TREATMENT_CODES) > 0
)

# ==============================================================================
# Section 4: INFRA-04 checks (zero behavior change)
# ==============================================================================

check(
  "Original AMC_PAYER_LOOKUP still exists as named vector",
  is.character(AMC_PAYER_LOOKUP) && !is.null(names(AMC_PAYER_LOOKUP))
)
check(
  "Original DRUG_GROUPINGS still exists as named vector",
  is.character(DRUG_GROUPINGS) && !is.null(names(DRUG_GROUPINGS))
)
check(
  "Original TIER_MAPPING still exists as list",
  is.list(TIER_MAPPING) && !data.table::is.data.table(TIER_MAPPING)
)
check(
  "Original TREATMENT_CODES still exists as list",
  is.list(TREATMENT_CODES) && !data.table::is.data.table(TREATMENT_CODES)
)
check(
  "Lookup value preserved: AMC_PAYER_LOOKUP['219'] == 'Medicaid'",
  AMC_PAYER_LOOKUP["219"] == "Medicaid"
)
check(
  "Keyed join matches: LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP[.('219'), payer_category] == 'Medicaid'",
  LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP[.("219"), payer_category] == "Medicaid"
)

# ==============================================================================
# Section 5: Namespace conflict check
# ==============================================================================

check("dplyr::between accessible", is.function(dplyr::between))
check("data.table::between accessible", is.function(data.table::between))

# ==============================================================================
# Section 6: Summary
# ==============================================================================

message("")
message(sprintf("========================================"))
message(sprintf("Phase 95 Validation: %d PASS, %d FAIL", pass_count, fail_count))
if (fail_count == 0) {
  message("All checks passed -- infrastructure ready for Phase 96")
} else {
  message(sprintf("WARNING: %d check(s) failed -- review output above", fail_count))
}
message(sprintf("========================================"))
