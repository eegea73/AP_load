#!/usr/bin/env Rscript
# The sixteen illustrative regimens of manuscript Table 5 must reproduce exactly.
here <- dirname(normalizePath(sub("^--file=", "",
        grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
root <- dirname(here)
source(file.path(root, "r", "ap_load2026.R"))

tables <- load_tables(file.path(root, "reference"))
presc <- read.csv(file.path(root, "examples", "table5_regimens.csv"),
                  stringsAsFactors = FALSE, colClasses = "character")
exp <- read.csv(file.path(root, "examples", "table5_expected.csv"), stringsAsFactors = FALSE)

res <- ap_load(presc, tables, "rostami")
got <- res$patients
fails <- 0
for (k in seq_len(nrow(exp))) {
  pid <- exp$patient_id[k]
  row <- got[got$patient_id == pid, ]
  ok <- nrow(row) == 1 && row$rows_refused == 0 && round(row$AP_Load2026) == exp$AP_Load2026_rounded[k]
  cat(sprintf("%-8s %-52s %8.1f  Table 5: %3d  %s\n", pid, exp$regimen[k],
              if (nrow(row)) row$AP_Load2026 else NA, exp$AP_Load2026_rounded[k],
              if (isTRUE(ok)) "ok" else "MISMATCH"))
  if (!isTRUE(ok)) fails <- fails + 1
}
cat("\n")
if (fails) { cat(sprintf("FAILURES: %d\n", fails)); quit(status = 1) }
cat(sprintf("All 16 Table 5 regimens reproduced. Rows refused: %d\n", res$report$drug_rows_refused))
