# Check for lowercase DX codes in DIAGNOSIS table
# Run after sourcing 01_load_pcornet.R to confirm the 1-patient discrepancy cause

library(dplyr)
library(stringr)
library(glue)

lowercase_dx <- pcornet$DIAGNOSIS %>%
  filter(str_detect(DX, "^c81")) %>%
  distinct(ID)

message(glue("Patients with lowercase c81 codes: {nrow(lowercase_dx)}"))
