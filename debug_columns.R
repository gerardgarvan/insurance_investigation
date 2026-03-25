# Run this in RStudio after source("R/01_load_pcornet.R") to check column names

# Check for date-related columns in each tumor registry table
cat("=== TUMOR_REGISTRY1 date/diagnosis columns ===\n")
grep("DATE|DIAG|DT_|DOD", names(pcornet$TUMOR_REGISTRY1), value = TRUE)

cat("\n=== TUMOR_REGISTRY2 date/diagnosis columns ===\n")
grep("DATE|DIAG|DT_|DOD", names(pcornet$TUMOR_REGISTRY2), value = TRUE)

cat("\n=== TUMOR_REGISTRY3 date/diagnosis columns ===\n")
grep("DATE|DIAG|DT_|DOD", names(pcornet$TUMOR_REGISTRY3), value = TRUE)
