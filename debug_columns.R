# Run this in RStudio after source("R/01_load_pcornet.R") to check column names

cat("=== ALL TUMOR_REGISTRY1 columns ===\n")
cat(paste(names(pcornet$TUMOR_REGISTRY1), collapse = "\n"), "\n")

cat("\n=== ALL TUMOR_REGISTRY2 columns ===\n")
cat(paste(names(pcornet$TUMOR_REGISTRY2), collapse = "\n"), "\n")

cat("\n=== ALL TUMOR_REGISTRY3 columns ===\n")
cat(paste(names(pcornet$TUMOR_REGISTRY3), collapse = "\n"), "\n")
