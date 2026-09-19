#!/usr/bin/env Rscript
# A dose that could mean two things must be refused, not read as the first number.
# The same sixteen rows as test_dose_parsing.py, so the two languages are held to
# one specification.
here <- dirname(normalizePath(sub("^--file=", "",
        grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
root <- dirname(here)
source(file.path(root, "r", "ap_load2026.R"))

expected_refusals <- c(t01 = AMBIGUOUS_SEPARATOR, t02 = FREQUENCY_NOT_TOTAL,
                       t03 = FREQUENCY_NOT_TOTAL, t06 = DOSE_NOT_POSITIVE,
                       t07 = MULTIPLE_DOSES, t11 = UNIT_NOT_RECOGNISED,
                       t14 = DOSE_NOT_POSITIVE)
expected_scored <- c(t04 = 4.2, t05 = 83.3, t08 = 100.0, t09 = 50.0,
                     t10 = 100.0, t12 = 76.2, t13 = 66.7)

tables <- load_tables(file.path(root, "reference"))
presc <- read.csv(file.path(root, "examples", "tricky_doses.csv"),
                  stringsAsFactors = FALSE, colClasses = "character")
res <- ap_load(presc, tables, "rostami")
d <- res$details
fails <- 0

cat("resolved:\n")
for (pid in names(expected_scored)) {
  r <- d[d$patient_id == pid, ]
  ok <- nrow(r) == 1 && !is.na(r$score) && abs(r$score - expected_scored[[pid]]) <= 0.15
  cat(sprintf("  %-5s %-22s -> %-12s expected %6.1f  %s\n", pid,
              substr(r$raw_dose, 1, 22),
              ifelse(is.na(r$score), r$refused, sprintf("%.1f", r$score)),
              expected_scored[[pid]], if (isTRUE(ok)) "ok" else "MISMATCH"))
  if (!isTRUE(ok)) fails <- fails + 1
}
cat("\nrefused:\n")
for (pid in names(expected_refusals)) {
  r <- d[d$patient_id == pid, ]
  ok <- nrow(r) == 1 && !is.na(r$refused) && r$refused == expected_refusals[[pid]]
  cat(sprintf("  %-5s %-22s -> %-44s %s\n", pid, substr(r$raw_dose, 1, 22),
              ifelse(is.na(r$refused), sprintf("SCORED (%.1f)", r$score), r$refused),
              if (isTRUE(ok)) "ok" else paste("EXPECTED", expected_refusals[[pid]])))
  if (!isTRUE(ok)) fails <- fails + 1
}
cat("\n")
if (fails) { cat(sprintf("FAILURES: %d\n", fails)); quit(status = 1) }
cat("Ambiguous doses refused, resolvable ones scored, interval synonyms matched.\n")
