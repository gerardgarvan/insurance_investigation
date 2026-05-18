# ==============================================================================
# Check for deleted proton CPT code 77521 in PROCEDURES table
# ==============================================================================
#
# CPT 77521 was deleted from the AMA code set before 2024. This script checks
# whether any claims in the PCORnet PROCEDURES table used this code, particularly
# after its deletion date.
#
# Run on HiPerGator: source("R/check_deleted_proton_code.R")
# ==============================================================================

source("R/00_config.R")
source("R/01_load_pcornet.R")

DELETED_CODE <- "77521"

procedures <- get_pcornet_table("PROCEDURES")

if (is.null(procedures)) {
  stop("PROCEDURES table not available")
}

# Find all rows where PX matches the deleted code
hits <- procedures %>%
  filter(PX == DELETED_CODE) %>%
  select(ID, PX, PX_DATE, PX_TYPE, ENCOUNTERID) %>%
  collect() %>%
  mutate(PX_DATE = as.Date(PX_DATE))

message(glue("\n=== Deleted Proton Code Check: {DELETED_CODE} ==="))
message(glue("Total rows matching {DELETED_CODE}: {nrow(hits)}"))

if (nrow(hits) == 0) {
  message("No claims found with code 77521. Exclusion from config is correct.")
} else {
  message(glue("\nPatients with code: {n_distinct(hits$ID)}"))
  message(glue("Date range: {min(hits$PX_DATE, na.rm = TRUE)} to {max(hits$PX_DATE, na.rm = TRUE)}"))

  # Break down by year
  yearly <- hits %>%
    mutate(year = format(PX_DATE, "%Y")) %>%
    count(year, name = "n_claims") %>%
    arrange(year)

  message("\nClaims by year:")
  print(yearly, n = Inf)

  # Flag any post-deletion usage
  post_deletion <- hits %>% filter(PX_DATE >= as.Date("2024-01-01"))
  message(glue("\nClaims on or after 2024-01-01: {nrow(post_deletion)}"))

  if (nrow(post_deletion) > 0) {
    message("WARNING: Deleted code used after deletion date. Consider adding to radiation_cpt.")
    print(post_deletion, n = 20)
  } else {
    message("No post-deletion usage found.")
  }
}
