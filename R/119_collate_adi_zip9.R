# ==============================================================================
# R/119_collate_adi_zip9.R
# Collate per-state Neighborhood Atlas ZIP9 ADI downloads into one reference file.
#
# The Atlas offers national bulk download for the 12-digit block-group FIPS linkage
# ONLY. The 9-digit ZIP linkage is state-by-state, so this file is hand-assembled
# and must be rebuilt whenever a cohort gains out-of-state patients.
#
# Output: data/reference/neighborhood_atlas_zip9_adi.csv  (ADI_INPUT_PATH in R/118)
# ==============================================================================

library(here); library(dplyr); library(vroom); library(readr); library(glue)

EXTRACT_DIR <- here::here("data", "raw", "adi_downloads", "extracted")
OUT_PATH    <- here::here("data", "reference", "neighborhood_atlas_zip9_adi.csv")
EXPECTED_VINTAGE <- "2024 v4.0.1"   # must match R/118's VINTAGE constant

files <- list.files(EXTRACT_DIR, pattern = "\\.(txt|csv)$",
                    recursive = TRUE, full.names = TRUE)
stopifnot("no extracted ADI files found" = length(files) > 0)
message(glue("Found {length(files)} extracted file(s)"))

# Read every file as character. ZIP9 MUST be character -- a numeric read drops
# leading zeros and silently corrupts every ZIP beginning 0 (all of New England
# and Puerto Rico).
adi_raw <- vroom::vroom(files, col_types = vroom::cols(.default = "c"),
                        id = "source_file", progress = FALSE)
message(glue("Combined rows: {format(nrow(adi_raw), big.mark = ',')}"))

# --- Column naming: the Atlas has shipped GISJOIN / FIPS / ZIPID / ZIP9 and
#     ADI_NATRANK / adi_natrank across versions. Normalise, do not assume.
names(adi_raw) <- toupper(names(adi_raw))
zip_col <- intersect(c("ZIP9", "ZIPID", "BENE_ZIP_CD", "ZIP_4"), names(adi_raw))[1]
adi_col <- intersect(c("ADI_NATRANK", "ADI_NATIONAL"), names(adi_raw))[1]
stopifnot(
  "no recognisable ZIP9 column" = !is.na(zip_col),
  "no recognisable ADI_NATRANK column" = !is.na(adi_col)
)
message(glue("Using ZIP column '{zip_col}', ADI column '{adi_col}'"))

adi <- adi_raw %>%
  dplyr::transmute(
    ZIP9        = gsub("[^0-9]", "", .data[[zip_col]]),
    ADI_NATRANK = .data[[adi_col]],
    source_file = basename(source_file)
  ) %>%
  dplyr::filter(nchar(ZIP9) == 9L)

# --- Duplicate check. A browser-resumed download can leave the same state in two
#     zips; that shows up here as exact-duplicate ZIP9s, not as a filename clash.
dupes <- adi %>% dplyr::count(ZIP9) %>% dplyr::filter(n > 1)
if (nrow(dupes) > 0) {
  by_file <- adi %>%
    dplyr::semi_join(dupes, by = "ZIP9") %>%
    dplyr::count(source_file, sort = TRUE)
  print(by_file)
  stop(glue(
    "{format(nrow(dupes), big.mark=',')} ZIP9s appear more than once. Two files ",
    "almost certainly contain the same state -- see the counts above, remove the ",
    "redundant zip, and re-run. Do NOT distinct() this away: it would hide a ",
    "vintage mismatch between two downloads of the same state."
  ))
}

# --- State coverage, from ZIP prefixes actually present
cover <- adi %>%
  dplyr::mutate(p3 = substr(ZIP9, 1, 3)) %>%
  dplyr::distinct(p3) %>%
  dplyr::arrange(p3)
message(glue("Distinct 3-digit ZIP prefixes: {nrow(cover)}"))

# The states this collation was rebuilt to add (Step 0 list)
target_p3 <- c(sprintf("%03d", 700:714),   # Louisiana
               sprintf("%03d", 716:729),   # Arkansas
               sprintf("%03d", 730:731), sprintf("%03d", 734:741),  # Oklahoma
               "733", sprintf("%03d", 750:799),                     # Texas
               sprintf("%03d", 386:397),   # Mississippi
               sprintf("%03d", 6:9))       # Puerto Rico
missing <- setdiff(target_p3, cover$p3)
if (length(missing) > 0) {
  message(glue("NOTE: {length(missing)} target prefixes absent -- some are simply ",
               "unassigned by USPS. Absent: {paste(head(missing, 20), collapse=', ')}"))
}

readr::write_csv(dplyr::select(adi, ZIP9, ADI_NATRANK), OUT_PATH)
message(glue("Wrote {format(nrow(adi), big.mark=',')} rows to {OUT_PATH}"))
message(glue("Size: {round(file.size(OUT_PATH)/1024^2, 1)} MB"))
