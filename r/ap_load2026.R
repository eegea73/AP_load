#!/usr/bin/env Rscript
# -*- coding: utf-8 -*-
#
# AP_Load2026 - the Antipsychotic Dose Load, reference implementation (base R).
#
# Fernandez-Egea E, Krishnadas R, Jenkins C, Patel R, Cardinal RN, Wolpe N (2026).
# The Antipsychotic Dose Load (AP_Load2026): a normalised prescribed-dose index
# for schizophrenia research. [citation to be completed on acceptance]
#
# Scores each prescribed antipsychotic as a percentage of a documented reference
# dose and sums the percentages, uncapped. Clozapine is referenced to a target
# individualised for sex and cigarettes per day; other agents are referenced to
# the geometric mean of the licensed maximum and the WHO DDD, capped at 1.5 x DDD.
#
# Design principle: anything that cannot be resolved without guessing is REFUSED
# and reported, never silently scored as zero.
#
# Reads the same reference CSVs as the Python implementation, so the two cannot
# drift apart. Base R only; no packages required.

AP_LOAD_VERSION <- "1.1.0"
AP_TABLE_VERSION <- "2026-11"

# Dosing intervals, in days. Labels that name the same schedule share a number,
# and that number is the key the reference table is looked up under: 'monthly'
# and '4-weekly' are one schedule, so a depot filed under either is found by
# either spelling. The full vocabulary is in reference/ap_load2026_intervals.csv;
# this is the fallback if a local reference directory does not carry that file.
INTERVAL_DAYS <- c(weekly = 7, "2-weekly" = 14, "4-weekly" = 28, monthly = 28,
                   "2-monthly" = 56, "3-monthly" = 84, "6-monthly" = 168)

UNMATCHED_DRUG       <- "unmatched_drug"
NON_NUMERIC_DOSE     <- "non_numeric_dose"
AMBIGUOUS_SEPARATOR  <- "ambiguous_decimal_or_thousands_separator"
MULTIPLE_DOSES       <- "more_than_one_dose_in_field"
FREQUENCY_NOT_TOTAL  <- "dose_is_per_administration_not_daily_total"
UNIT_NOT_RECOGNISED  <- "dose_unit_not_recognised"
DOSE_NOT_POSITIVE    <- "dose_not_positive"
AMBIGUOUS_FORM       <- "ambiguous_form_oral_or_lai"
LAI_INTERVAL_UNKNOWN <- "lai_interval_not_stated"
LAI_NOT_IN_TABLE     <- "lai_interval_not_in_reference_table"
MISSING_SEX          <- "missing_or_unrecognised_sex"
MISSING_SMOKING      <- "missing_smoking_information"
NO_REFERENCE         <- "no_reference_dose_for_agent"

REFUSAL_HELP <- c(
  "unmatched_drug" = "drug name did not match any stem; add a row to ap_load2026_drug_stems.csv",
  "non_numeric_dose" = "dose could not be read as a number",
  "ambiguous_decimal_or_thousands_separator" = "'1,000' or '1.000' may be one thousand or one; state the dose unambiguously",
  "more_than_one_dose_in_field" = "more than one dose in the field; give the total daily dose as a single number",
  "dose_is_per_administration_not_daily_total" = "dose is stated per administration (bd, tds, /8h); give the total daily dose",
  "dose_unit_not_recognised" = "dose unit not recognised; use mg (g, mcg and microgram are converted)",
  "dose_not_positive" = "dose is zero or negative; omit the row instead",
  "ambiguous_form_oral_or_lai" = "agent exists as both oral and depot and neither route nor interval was given",
  "lai_interval_not_stated" = "depot identified but the dosing interval was not stated",
  "lai_interval_not_in_reference_table" = "no licensed maximum tabulated for that agent at that interval",
  "missing_or_unrecognised_sex" = "clozapine requires sex: male/female, m/f, hombre/mujer, or numeric 1 = male, 0 = female",
  "missing_smoking_information" = "clozapine requires cigarettes_per_day or smoking_status",
  "no_reference_dose_for_agent" = "agent has no reference dose in the reference table")

SEX_NUMERIC_NOTE <- "numeric sex code read as 1 = male, 0 = female"

# --- reference tables -----------------------------------------------------

default_reference_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  here <- if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg[1]))) else getwd()
  file.path(dirname(here), "reference")
}

load_tables <- function(reference_dir = NULL) {
  d <- if (is.null(reference_dir)) default_reference_dir() else reference_dir
  if (!dir.exists(d)) stop("reference directory not found: ", d)
  rd <- function(f) utils::read.csv(file.path(d, f), stringsAsFactors = FALSE,
                                    colClasses = "character", encoding = "UTF-8")

  oral <- rd(sprintf("ap_load2026_reference_%s.csv", AP_TABLE_VERSION))
  oral$generic <- tolower(trimws(oral$generic))
  oral$bnf_max <- suppressWarnings(as.numeric(oral$bnf_max_mg_day))
  oral$ddd     <- suppressWarnings(as.numeric(oral$who_ddd_mg_day))

  lai <- rd(sprintf("ap_load2026_lai_%s.csv", AP_TABLE_VERSION))
  lai$generic  <- tolower(trimws(lai$generic))
  lai$interval <- tolower(trimws(lai$interval))
  lai$max      <- suppressWarnings(as.numeric(lai$max_per_interval_mg))

  anc <- rd("ap_load2026_clozapine_anchors.csv")
  anc$key <- paste(tolower(trimws(anc$scheme)), tolower(trimws(anc$sex)),
                   tolower(trimws(anc$smoking)), sep = "|")
  anchors <- setNames(as.numeric(anc$target_mg_day), anc$key)

  st <- rd("ap_load2026_drug_stems.csv")
  st$kind <- tolower(trimws(st$kind))
  mol <- st[st$kind == "molecule", ]
  mol$pattern <- tolower(trimws(mol$pattern))
  mol$value   <- tolower(trimws(mol$value))
  mol$interval <- tolower(trimws(mol$interval))
  mol <- mol[order(-nchar(mol$pattern)), ]        # longest stem first
  frm <- st[st$kind == "form", ]
  frm$value <- ifelse(tolower(trimws(frm$value)) == "lai", "LAI", "oral")
  frm$interval <- tolower(trimws(frm$interval))

  interval_days <- INTERVAL_DAYS
  iv_file <- file.path(d, "ap_load2026_intervals.csv")
  if (file.exists(iv_file)) {
    iv <- rd("ap_load2026_intervals.csv")
    labels <- vapply(iv$label, normalise_text, character(1), USE.NAMES = FALSE)
    extra <- suppressWarnings(as.numeric(iv$days))
    keep <- nzchar(labels) & !is.na(extra)
    interval_days[labels[keep]] <- extra[keep]
  }

  # brand stems that fix a dosing interval, for finding 'Consta' in
  # 'Risperidone Consta', where the prefix match has already gone to the generic
  brands <- mol[!is.na(mol$interval) & nzchar(mol$interval), ]

  # the formulation vocabulary extended to the end of the word, for removing a
  # schedule from a dose field: '/2meses' is matched by '2[ -]?mes' and the
  # trailing 'es' must go with it
  eaters <- paste0(frm$pattern, "[a-z]*")

  list(oral = oral, lai = lai, anchors = anchors, molecule = mol, form = frm,
       brands = brands, eaters = eaters, interval_days = interval_days,
       dual_form = unique(lai$generic), source_dir = normalizePath(d))
}

# The schedule an interval label names, in days; NA if it names none.
interval_days_of <- function(interval, tables) {
  if (is.null(interval) || length(interval) == 0 || is.na(interval)) return(NA_real_)
  s <- normalise_text(interval)
  if (!nzchar(s) || !(s %in% names(tables$interval_days))) return(NA_real_)
  as.numeric(tables$interval_days[[s]])
}

# Licensed maximum for this agent on this schedule; NA if there is none.
# An exact label match is preferred; failing that, any row for the same schedule
# under another name, provided the table gives only one maximum for it.
lai_reference <- function(generic, interval, tables) {
  if (!is.na(interval)) {
    i <- which(tables$lai$generic == generic & tables$lai$interval == normalise_text(interval))
    if (length(i)) return(tables$lai$max[i[1]])
  }
  days <- interval_days_of(interval, tables)
  if (is.na(days)) return(NA_real_)
  rows <- which(tables$lai$generic == generic &
                vapply(tables$lai$interval, function(x) {
                  d <- if (x %in% names(tables$interval_days)) as.numeric(tables$interval_days[[x]]) else NA_real_
                  !is.na(d) && d == days
                }, logical(1), USE.NAMES = FALSE))
  if (!length(rows)) return(NA_real_)
  mx <- unique(tables$lai$max[rows])
  if (length(mx) != 1) return(NA_real_)     # two maxima for one schedule: refuse
  mx
}

# --- text handling --------------------------------------------------------

# Accent folding. The source file stays pure ASCII and the accented characters are
# built from their UTF-8 bytes, so the script loads without warnings in any locale.
.u8 <- function(...) rawToChar(as.raw(c(...)))
ACCENT_FROM <- c(.u8(0xC3, 0xA1), .u8(0xC3, 0xA9), .u8(0xC3, 0xAD), .u8(0xC3, 0xB3),
                 .u8(0xC3, 0xBA), .u8(0xC3, 0xB1), .u8(0xC3, 0xBC),
                 .u8(0xC3, 0x81), .u8(0xC3, 0x89), .u8(0xC3, 0x8D), .u8(0xC3, 0x93),
                 .u8(0xC3, 0x9A), .u8(0xC3, 0x91), .u8(0xC3, 0x9C))
ACCENT_TO   <- c("a", "e", "i", "o", "u", "n", "u",
                 "a", "e", "i", "o", "u", "n", "u")

normalise_text <- function(x) {
  if (is.null(x) || length(x) == 0) return("")
  s <- as.character(x)[1]
  if (is.na(s)) return("")
  for (k in seq_along(ACCENT_FROM))
    s <- gsub(ACCENT_FROM[k], ACCENT_TO[k], s, fixed = TRUE, useBytes = TRUE)
  s <- tolower(trimws(s))
  gsub("\\s+", " ", s)
}

match_molecule <- function(raw, tables) {
  s <- normalise_text(raw)
  if (s %in% c("", "none", "n/a", "na", "nil", "ninguno", "-"))
    return(list(generic = NA_character_, stem = NA_character_, interval = NA_character_))
  hit <- which(startsWith(s, tables$molecule$pattern))
  if (!length(hit))
    return(list(generic = NA_character_, stem = NA_character_, interval = NA_character_))
  i <- hit[1]
  iv <- tables$molecule$interval[i]
  generic <- tables$molecule$value[i]
  if (is.na(iv) || iv == "") {
    # a brand name that fixes the interval, anywhere in the string: 'Risperidone
    # Consta' keeps the two-weekly schedule that 'Consta' alone would have given
    b <- tables$brands
    if (nrow(b)) {
      j <- which(b$value == generic & vapply(b$pattern, function(p) grepl(p, s, fixed = TRUE),
                                             logical(1), USE.NAMES = FALSE))
      if (length(j)) iv <- b$interval[j[1]]
    }
  }
  list(generic = generic, stem = tables$molecule$pattern[i],
       interval = if (is.na(iv) || iv == "") NA_character_ else iv)
}

# A dose stated per administration is not a daily total, and the tool has no way
# to know how many administrations there were. Once-daily markers (od, nocte,
# mane, daily) are absent here: those doses ARE the daily total.
FREQUENCY_RE <- paste0(
  "\\b(?:bd|b\\.d|bid|b\\.i\\.d|tds|t\\.d\\.s|tid|t\\.i\\.d|qds|q\\.d\\.s|qid|q\\.i\\.d)\\b",
  "|\\bq ?[0-9]+ ?h\\b|\\bcada +[0-9]+ *(?:h|horas?)\\b|/ *[0-9]+ *h\\b",
  "|\\b(?:twice|three times|four times|dos veces|tres veces|cuatro veces)\\b",
  "|[0-9]+ *[-+] *[0-9]+ *[-+] *[0-9]+",
  "|\\b[0-9]+ *x *[0-9]+|\\b[0-9]+ *veces\\b")

# Units the parser accepts, and the factor that turns them into mg.
DOSE_UNITS <- c("mg" = 1, "mgs" = 1, "miligramos" = 1, "milligrams" = 1,
                "milligram" = 1, "g" = 1000, "gr" = 1000, "gramo" = 1000,
                "gramos" = 1000, "gram" = 1000, "grams" = 1000,
                "mcg" = 0.001, "mcgs" = 0.001, "ug" = 0.001, "microgram" = 0.001,
                "micrograms" = 0.001, "microgramo" = 0.001, "microgramos" = 0.001)

# Remove formulation and interval vocabulary from a dose string: '450mg/d',
# '400 mg/mes' and '960/2meses' state a dose and a schedule in one field. The
# schedule is read separately by match_form; here it is removed so that what is
# left can be required to be a dose and nothing else.
strip_schedule_words <- function(s, tables) {
  if (!is.null(tables)) for (p in tables$eaters) s <- gsub(p, " ", s, perl = TRUE, ignore.case = TRUE)
  s <- gsub("\\s+", " ", s)
  gsub("^[ ,;:./-]+|[ ,;:./-]+$", "", s)
}

match_form <- function(tables, ...) {
  texts <- unlist(list(...))
  joined <- paste(vapply(texts, normalise_text, character(1)), collapse = " ")
  form <- NA_character_; interval <- NA_character_
  for (i in seq_len(nrow(tables$form))) {
    if (grepl(tables$form$pattern[i], joined, perl = TRUE, ignore.case = TRUE)) {
      if (is.na(form)) form <- tables$form$value[i]
      iv <- tables$form$interval[i]
      if (is.na(interval) && !is.na(iv) && nzchar(iv)) interval <- iv
    }
  }
  list(form = form, interval = interval)
}

# Accepts a plain number, optionally with a unit and a schedule: 300, '300mg',
# '3 mg/d', '66,6mg/m', '960/2meses'. Refuses anything else rather than reading
# the first number it can find: '1,000 mg', '2 x 100 mg' and '300 mg bd' each
# mean something specific, and guessing at them silently changes the score.
parse_dose <- function(value, tables = NULL) {
  bad <- function(code) list(mg = NA_real_, problem = code)
  if (is.null(value) || length(value) == 0) return(bad(NON_NUMERIC_DOSE))
  v <- value[1]
  if (is.numeric(v)) {
    if (is.na(v) || !is.finite(v)) return(bad(NON_NUMERIC_DOSE))
    return(if (v > 0) list(mg = as.numeric(v), problem = NA_character_) else bad(DOSE_NOT_POSITIVE))
  }
  s <- normalise_text(v)
  if (!nzchar(s)) return(bad(NON_NUMERIC_DOSE))
  if (!grepl("[0-9]", s)) return(bad(NON_NUMERIC_DOSE))
  if (grepl(FREQUENCY_RE, s, perl = TRUE, ignore.case = TRUE)) return(bad(FREQUENCY_NOT_TOTAL))
  if (grepl("^ *-", s)) return(bad(DOSE_NOT_POSITIVE))

  s <- strip_schedule_words(s, tables)

  # '1,000' and '1.000' are one thousand in one convention and one in the other.
  # A leading zero ('0.500') can only be a decimal, so it is left alone.
  if (grepl("(?<![0-9.,])[1-9][0-9]{0,2}[.,][0-9]{3}(?![0-9.,])", s, perl = TRUE))
    return(bad(AMBIGUOUS_SEPARATOR))

  # a comma before one or two digits is a decimal point: 66,6 -> 66.6
  s <- gsub("(?<=[0-9]),(?=[0-9]{1,2}(?![0-9]))", ".", s, perl = TRUE)

  if (length(regmatches(s, gregexpr("[0-9]+(\\.[0-9]+)?", s))[[1]]) > 1)
    return(bad(MULTIPLE_DOSES))

  m <- regmatches(s, regexec("^([0-9]+(?:\\.[0-9]+)?) *([a-z.]*)$", s, perl = TRUE))[[1]]
  if (!length(m)) return(bad(NON_NUMERIC_DOSE))
  unit <- gsub("\\.", "", m[3])
  if (!nzchar(unit)) factor <- 1
  else if (unit %in% names(DOSE_UNITS)) factor <- as.numeric(DOSE_UNITS[[unit]])
  else return(bad(UNIT_NOT_RECOGNISED))
  mg <- as.numeric(m[2]) * factor
  if (is.na(mg) || mg <= 0) return(bad(DOSE_NOT_POSITIVE))
  list(mg = mg, problem = NA_character_)
}

normalise_sex <- function(value) {
  s <- normalise_text(value)
  if (s %in% c("m", "male", "man", "hombre", "varon", "h", "v")) return(list(sex = "male", note = NA_character_))
  if (s %in% c("f", "female", "woman", "mujer"))                 return(list(sex = "female", note = NA_character_))
  if (s %in% c("1", "1.0"))  return(list(sex = "male", note = SEX_NUMERIC_NOTE))
  if (s %in% c("0", "0.0"))  return(list(sex = "female", note = SEX_NUMERIC_NOTE))
  list(sex = NA_character_, note = NA_character_)
}

normalise_smoking <- function(row) {
  cigs <- row[["cigarettes_per_day"]]
  if (!is.null(cigs) && length(cigs) && !is.na(cigs) && nzchar(as.character(cigs))) {
    c2 <- suppressWarnings(as.numeric(gsub(",", ".", as.character(cigs), fixed = TRUE)))
    if (!is.na(c2)) return(list(fraction = min(1, max(0, c2 / 10)), note = NA_character_))
  }
  s <- normalise_text(row[["smoking_status"]])
  if (s %in% c("1", "yes", "y", "smoker", "current", "current smoker", "fumador", "si", "true"))
    return(list(fraction = 1, note = "binary smoking status: treated as fully induced"))
  if (s %in% c("0", "no", "n", "non-smoker", "nonsmoker", "never", "no fumador", "nofumador", "false"))
    return(list(fraction = 0, note = "binary smoking status: treated as not induced"))
  list(fraction = NA_real_, note = NA_character_)
}

# --- scoring --------------------------------------------------------------

oral_reference <- function(generic, tables) {
  i <- match(generic, tables$oral$generic)
  if (is.na(i)) return(list(ref = NA_real_, basis = NO_REFERENCE))
  bnf <- tables$oral$bnf_max[i]; ddd <- tables$oral$ddd[i]
  if (!is.na(bnf) && !is.na(ddd)) {
    gm <- sqrt(bnf * ddd); cap <- 1.5 * ddd
    return(list(ref = min(gm, cap),
                basis = if (gm > cap) "capped geometric mean" else "geometric mean"))
  }
  if (!is.na(bnf)) return(list(ref = bnf, basis = "label maximum (no WHO DDD)"))
  if (!is.na(ddd)) return(list(ref = 1.5 * ddd, basis = "1.5 x DDD (no current licensed maximum)"))
  list(ref = NA_real_, basis = NO_REFERENCE)
}

clozapine_target <- function(sex, fraction, scheme, tables) {
  ns <- tables$anchors[[paste(scheme, sex, "non-smoker", sep = "|")]]
  sm <- tables$anchors[[paste(scheme, sex, "smoker", sep = "|")]]
  ns + (sm - ns) * fraction
}

get_field <- function(row, name) {
  if (!name %in% names(row)) return(NA)
  v <- row[[name]]
  if (length(v) == 0) return(NA)
  v[1]
}

score_row <- function(row, tables, scheme) {
  out <- list(patient_id = as.character(get_field(row, "patient_id")),
              raw_drug = as.character(get_field(row, "drug")),
              raw_dose = as.character(get_field(row, "dose")),
              generic = NA_character_, stem = NA_character_, form = NA_character_,
              interval = NA_character_, dose_mg = NA_real_, reference_mg = NA_real_,
              basis = NA_character_, score = NA_real_, refused = NA_character_,
              note = NA_character_)

  mm <- match_molecule(get_field(row, "drug"), tables)
  if (is.na(mm$generic)) { out$refused <- UNMATCHED_DRUG; return(out) }
  out$generic <- mm$generic; out$stem <- mm$stem

  pd <- parse_dose(get_field(row, "dose"), tables)
  if (!is.na(pd$problem)) { out$refused <- pd$problem; return(out) }
  out$dose_mg <- pd$mg

  route <- normalise_text(get_field(row, "route"))
  tf <- match_form(tables, get_field(row, "drug"), get_field(row, "dose"), get_field(row, "interval"))
  form <- if (route %in% c("oral", "po", "tablet", "capsule", "liquid", "oral liquid", "vo")) "oral"
          else if (route %in% c("lai", "depot", "im", "injection", "inyectable", "depot injection")) "LAI"
          else if (!is.na(mm$interval)) "LAI"
          else tf$form

  interval <- normalise_text(get_field(row, "interval"))
  if (!nzchar(interval)) interval <- NA_character_
  if (is.na(interval)) interval <- mm$interval
  if (is.na(interval)) interval <- tf$interval
  if (!is.na(interval) && is.na(interval_days_of(interval, tables)))
    interval <- if (!is.na(tf$interval)) tf$interval else mm$interval
  out$interval <- interval

  if (is.na(form)) {
    if (out$generic %in% tables$dual_form) { out$refused <- AMBIGUOUS_FORM; return(out) }
    form <- "oral"
  }
  out$form <- form

  if (form == "LAI") {
    if (is.na(interval)) { out$refused <- LAI_INTERVAL_UNKNOWN; return(out) }
    mx <- lai_reference(out$generic, interval, tables)
    if (is.na(mx)) { out$refused <- LAI_NOT_IN_TABLE; return(out) }
    out$reference_mg <- mx
    out$basis <- sprintf("licensed formulation maximum per %s", interval)
    out$score <- out$dose_mg / out$reference_mg * 100
    return(out)
  }

  if (out$generic == "clozapine") {
    sx <- normalise_sex(get_field(row, "sex"))
    if (is.na(sx$sex)) { out$refused <- MISSING_SEX; return(out) }
    sm <- normalise_smoking(row)
    if (is.na(sm$fraction)) { out$refused <- MISSING_SMOKING; return(out) }
    out$reference_mg <- clozapine_target(sx$sex, sm$fraction, scheme, tables)
    out$basis <- sprintf("individualised clozapine target (%s anchors, %s)", scheme, sx$sex)
    notes <- c(sx$note, sm$note); notes <- notes[!is.na(notes)]
    out$note <- if (length(notes)) paste(notes, collapse = "; ") else NA_character_
    out$score <- out$dose_mg / out$reference_mg * 100
    return(out)
  }

  orf <- oral_reference(out$generic, tables)
  if (is.na(orf$ref)) { out$refused <- orf$basis; return(out) }
  out$reference_mg <- orf$ref; out$basis <- orf$basis
  out$score <- out$dose_mg / out$reference_mg * 100
  out
}

#' Compute AP_Load2026 from a long-format prescription data frame.
#' @return list(patients, details, report)
ap_load <- function(prescriptions, tables = NULL, scheme = c("rostami", "reeves")) {
  scheme <- match.arg(scheme)
  if (is.null(tables)) tables <- load_tables()
  rows <- lapply(seq_len(nrow(prescriptions)), function(i) as.list(prescriptions[i, , drop = FALSE]))
  det <- lapply(rows, score_row, tables = tables, scheme = scheme)

  details <- do.call(rbind, lapply(det, function(d) {
    d$reference_mg <- if (is.na(d$reference_mg)) NA_real_ else round(d$reference_mg, 3)
    d$score <- if (is.na(d$score)) NA_real_ else round(d$score, 2)
    as.data.frame(d, stringsAsFactors = FALSE)
  }))

  ids <- unique(details$patient_id)
  patients <- do.call(rbind, lapply(ids, function(pid) {
    sub <- details[details$patient_id == pid, ]
    scored <- sum(!is.na(sub$score)); refused <- sum(is.na(sub$score))
    data.frame(patient_id = pid,
               AP_Load2026 = if (scored == 0) NA_real_ else round(sum(sub$score, na.rm = TRUE), 1),
               drugs_scored = scored, rows_refused = refused,
               complete = if (refused == 0) "yes" else "NO",
               clozapine_anchors = scheme, reference_table = AP_TABLE_VERSION,
               stringsAsFactors = FALSE)
  }))

  report <- list(ap_load2026_version = AP_LOAD_VERSION, reference_table = AP_TABLE_VERSION,
                 reference_dir = tables$source_dir, clozapine_anchors = scheme,
                 patients = length(ids),
                 patients_complete = sum(patients$complete == "yes"),
                 drug_rows = nrow(details),
                 drug_rows_scored = sum(!is.na(details$score)),
                 drug_rows_refused = sum(is.na(details$score)),
                 refusals_by_reason = table(details$refused[!is.na(details$refused)]),
                 unmatched_names = table(details$raw_drug[!is.na(details$refused) &
                                                          details$refused == UNMATCHED_DRUG]))
  list(patients = patients, details = details, report = report)
}

format_report <- function(report) {
  lines <- c(sprintf("AP_Load2026 %s   reference table %s   clozapine anchors: %s",
                     report$ap_load2026_version, report$reference_table, report$clozapine_anchors),
             sprintf("reference directory: %s", report$reference_dir),
             sprintf("patients: %d (%d complete, %d with at least one refused row)",
                     report$patients, report$patients_complete,
                     report$patients - report$patients_complete),
             sprintf("drug rows: %d scored, %d refused",
                     report$drug_rows_scored, report$drug_rows_refused))
  if (length(report$refusals_by_reason)) {
    lines <- c(lines, "refusals:")
    rr <- sort(report$refusals_by_reason, decreasing = TRUE)
    for (nm in names(rr))
      lines <- c(lines, sprintf("   %-34s %4d   %s", nm, rr[[nm]],
                                if (nm %in% names(REFUSAL_HELP)) REFUSAL_HELP[[nm]] else ""))
  }
  if (length(report$unmatched_names)) {
    lines <- c(lines, "unmatched drug names:")
    un <- sort(report$unmatched_names, decreasing = TRUE)
    for (nm in names(un)) lines <- c(lines, sprintf("   %-34s %4d", substr(nm, 1, 34), un[[nm]]))
  }
  paste(lines, collapse = "\n")
}

# --- command line ---------------------------------------------------------

if (sys.nframe() == 0L && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 2) {
    cat("Usage: Rscript ap_load2026.R input.csv output.csv [detail.csv] [review.csv]",
        "               [--anchors rostami|reeves] [--reference-dir DIR]", sep = "\n")
    quit(status = 1)
  }
  scheme <- "rostami"; refdir <- NULL
  if ("--anchors" %in% args) scheme <- args[which(args == "--anchors") + 1]
  if ("--reference-dir" %in% args) refdir <- args[which(args == "--reference-dir") + 1]
  positional <- args[!grepl("^--", args)]
  drop <- c(which(args == "--anchors") + 1, which(args == "--reference-dir") + 1)
  if (length(drop)) positional <- setdiff(positional, args[drop])

  tables <- load_tables(refdir)
  presc <- utils::read.csv(positional[1], stringsAsFactors = FALSE, colClasses = "character",
                           encoding = "UTF-8")
  res <- ap_load(presc, tables, scheme)
  utils::write.csv(res$patients, positional[2], row.names = FALSE, na = "")
  if (length(positional) >= 3) utils::write.csv(res$details, positional[3], row.names = FALSE, na = "")
  if (length(positional) >= 4)
    utils::write.csv(res$details[is.na(res$details$score), ], positional[4], row.names = FALSE, na = "")
  cat(format_report(res$report), "\n")
}
