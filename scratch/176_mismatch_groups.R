# scratch/176_mismatch_groups.R
# Read D_record_mismatches from the R/121 workbook and print grouped counts.
# Prints only aggregate counts — no patient IDs, no ZIP values, no dates.
# Run interactively on HiPerGator after source("R/00_config.R").

wb <- file.path(CONFIG$output_dir, "zip_problem_inventory_2026-10-09.xlsx")

library(readxl)
d <- read_excel(wb, sheet = "D_record_mismatches",
                col_types = "text")

cat("\nD_record_mismatches: ", nrow(d), "rows,", n_distinct(d$PATID), "distinct patients\n\n")

# Pattern classification (no identifiers emitted)
d2 <- d |>
  dplyr::mutate(
    zip5_trimmed = stringr::str_trim(zip5_norm),
    zip9_pre5    = stringr::str_sub(stringr::str_trim(zip9_first5), 1, 5),
    is_sentinel_z5 = zip5_trimmed %in% c("00000", "99999", ""),
    is_sentinel_z9 = zip9_pre5    %in% c("00000", "99999", ""),
    zip3_z5 = stringr::str_sub(zip5_trimmed, 1, 3),
    zip3_z9 = stringr::str_sub(zip9_pre5,   1, 3),
    pattern = dplyr::case_when(
      is_sentinel_z5 | is_sentinel_z9          ~ "sentinel / non-numeric",
      nchar(zip5_trimmed) != 5 | nchar(zip9_pre5) != 5 ~ "malformed (not 5 digits)",
      zip3_z5 != zip3_z9                        ~ "different ZIP3",
      zip5_trimmed == zip9_pre5                 ~ "exact match (should not appear)",
      TRUE                                       ~ "same ZIP3, different ZIP5"
    )
  )

counts <- d2 |>
  dplyr::count(pattern, name = "rows") |>
  dplyr::arrange(dplyr::desc(rows))

print(counts)
cat("\nTotal rows:", sum(counts$rows), "\n")
