#!/usr/bin/env Rscript
# The tool must fail safely: every ambiguous row refused, with the right reason.
here <- dirname(normalizePath(sub("^--file=", "",
        grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
root <- dirname(here)
source(file.path(root, "r", "ap_load2026.R"))

expected_refusals <- c(bad01 = AMBIGUOUS_FORM, bad02 = UNMATCHED_DRUG, bad03 = MISSING_SEX,
                       bad04 = LAI_INTERVAL_UNKNOWN, bad05 = MISSING_SMOKING,
                       bad06 = NON_NUMERIC_DOSE)
expected_scored <- c(ok01 = 92.9, ok02 = 122.6, ok03 = 66.7, ok04 = 100.0, ok05 = 54.8, ok06 = 88.9)

tables <- load_tables(file.path(root, "reference"))
presc <- read.csv(file.path(root, "examples", "messy_example.csv"),
                  stringsAsFactors = FALSE, colClasses = "character")
res <- ap_load(presc, tables, "rostami")
d <- res$details
fails <- 0

cat("resolved:\n")
for (pid in names(expected_scored)) {
  r <- d[d$patient_id == pid, ]
  ok <- nrow(r) == 1 && !is.na(r$score) && abs(r$score - expected_scored[[pid]]) <= 0.15
  cat(sprintf("  %-6s %-30s -> %-16s %-9s %8s  expected %6.1f  %s\n", pid,
              substr(r$raw_drug, 1, 29), r$generic, ifelse(is.na(r$form), "", r$form),
              ifelse(is.na(r$score), r$refused, sprintf("%.1f", r$score)),
              expected_scored[[pid]], if (isTRUE(ok)) "ok" else "MISMATCH"))
  if (!isTRUE(ok)) fails <- fails + 1
}
cat("\nrefused:\n")
for (pid in names(expected_refusals)) {
  r <- d[d$patient_id == pid, ]
  ok <- nrow(r) == 1 && !is.na(r$refused) && r$refused == expected_refusals[[pid]]
  cat(sprintf("  %-6s %-30s -> %-34s %s\n", pid, substr(r$raw_drug, 1, 29),
              ifelse(is.na(r$refused), sprintf("SCORED (%.1f)", r$score), r$refused),
              if (isTRUE(ok)) "ok" else paste("EXPECTED", expected_refusals[[pid]])))
  if (!isTRUE(ok)) fails <- fails + 1
}
cat("\n"); cat(format_report(res$report), "\n")
if (fails) { cat(sprintf("\nFAILURES: %d\n", fails)); quit(status = 1) }
cat("\nAll refusal behaviour as specified.\n")
