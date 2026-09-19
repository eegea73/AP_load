#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AP_Load2026 - the Antipsychotic Dose Load, reference implementation.

Fernandez-Egea E, Krishnadas R, Jenkins C, Patel R, Cardinal RN, Wolpe N (2026).
The Antipsychotic Dose Load (AP_Load2026): a normalised prescribed-dose index for
schizophrenia research. [citation to be completed on acceptance]

Scores each prescribed antipsychotic as a percentage of a documented reference
dose and sums the percentages, uncapped. Clozapine is referenced to a target
individualised for sex and cigarettes per day; other agents are referenced to
the geometric mean of the licensed maximum and the WHO DDD, capped at 1.5 x DDD.

Design principle: anything that cannot be resolved without guessing is REFUSED
and reported, never silently scored as zero. A cohort scored with rows refused
is not comparable with one scored without, so the refusal count is part of the
output rather than a warning on the console.

Reference tables live in ../reference and are versioned and dated. To score
against a local formulary, copy that directory, edit the CSVs and pass
--reference-dir. The configuration used is stamped into every output file.

Stdlib only. Python 3.8+.
"""

import argparse
import csv
import math
import os
import re
import sys
from collections import Counter, OrderedDict

VERSION = "1.0.0"
TABLE_VERSION = "2026-09"

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REFERENCE_DIR = os.path.join(os.path.dirname(HERE), "reference")

# Dosing intervals, in days. Intervals that describe the same dosing schedule
# share a number, and that number is the key the reference table is looked up
# under: 'monthly' and '4-weekly' name one schedule, so a depot filed under
# either label is found by either spelling. The full vocabulary, English and
# Spanish, is in reference/ap_load2026_intervals.csv; this is the fallback used
# if a local copy of the reference directory does not have that file.
INTERVAL_DAYS = {
    "weekly": 7.0, "2-weekly": 14.0, "4-weekly": 28.0,
    "monthly": 28.0, "2-monthly": 56.0, "3-monthly": 84.0, "6-monthly": 168.0,
}

# Refusal codes ------------------------------------------------------------
UNMATCHED_DRUG = "unmatched_drug"
NON_NUMERIC_DOSE = "non_numeric_dose"
AMBIGUOUS_SEPARATOR = "ambiguous_decimal_or_thousands_separator"
MULTIPLE_DOSES = "more_than_one_dose_in_field"
FREQUENCY_NOT_TOTAL = "dose_is_per_administration_not_daily_total"
UNIT_NOT_RECOGNISED = "dose_unit_not_recognised"
DOSE_NOT_POSITIVE = "dose_not_positive"
AMBIGUOUS_FORM = "ambiguous_form_oral_or_lai"
LAI_INTERVAL_UNKNOWN = "lai_interval_not_stated"
LAI_NOT_IN_TABLE = "lai_interval_not_in_reference_table"
MISSING_SEX = "missing_or_unrecognised_sex"
MISSING_SMOKING = "missing_smoking_information"
NO_REFERENCE = "no_reference_dose_for_agent"

REFUSAL_HELP = {
    UNMATCHED_DRUG: "drug name did not match any stem; add a row to ap_load2026_drug_stems.csv",
    NON_NUMERIC_DOSE: "dose could not be read as a number",
    AMBIGUOUS_SEPARATOR: "'1,000' or '1.000' may be one thousand or one; state the dose unambiguously",
    MULTIPLE_DOSES: "more than one dose in the field; give the total daily dose as a single number",
    FREQUENCY_NOT_TOTAL: "dose is stated per administration (bd, tds, /8h); give the total daily dose",
    UNIT_NOT_RECOGNISED: "dose unit not recognised; use mg (g, mcg and microgram are converted)",
    DOSE_NOT_POSITIVE: "dose is zero or negative; omit the row instead",
    AMBIGUOUS_FORM: "agent exists as both oral and depot and neither route nor interval was given",
    LAI_INTERVAL_UNKNOWN: "depot identified but the dosing interval was not stated",
    LAI_NOT_IN_TABLE: "no licensed maximum tabulated for that agent at that interval",
    MISSING_SEX: "clozapine requires sex: male/female, m/f, hombre/mujer, or numeric 1 = male, 0 = female",
    MISSING_SMOKING: "clozapine requires cigarettes_per_day or smoking_status",
    NO_REFERENCE: "agent has no reference dose in the reference table",
}


class Tables(object):
    def __init__(self, oral, lai, anchors, stems, source_dir, interval_days=None):
        self.interval_days = dict(interval_days or INTERVAL_DAYS)
        self.oral = oral            # generic -> dict
        self.lai = lai              # (generic, interval) -> dict
        self.anchors = anchors      # (scheme, sex, smoking) -> mg/day
        self.molecule_stems = stems["molecule"]   # list of (pattern, generic, interval)
        self.form_patterns = stems["form"]        # list of (compiled, form, interval)
        self.brand_intervals = [(p, g, iv) for (p, g, iv) in stems["molecule"] if iv]
        # the same formulation vocabulary, extended to the end of the word, for
        # removing a schedule from a dose field: '/2meses' is matched by the
        # two-monthly pattern '2[ -]?mes' and the 'es' must go with it
        self.form_eaters = [re.compile(p.pattern + r"[a-z]*", re.I)
                            for (p, _f, _i) in stems["form"]]
        self.dual_form = set(g for (g, _i) in lai)
        self.source_dir = source_dir
        # The same schedule under a second name: a depot filed as '4-weekly' is
        # found by 'monthly' and the reverse. Built only where it is unambiguous,
        # so a table that ever gives two different maxima for one schedule falls
        # back to exact-label matching rather than choosing between them.
        by_days, clashes = {}, set()
        for (generic, interval), row in lai.items():
            days = self.interval_days.get(interval)
            if days is None:
                continue
            key = (generic, days)
            if key in by_days and by_days[key]["max"] != row["max"]:
                clashes.add(key)
            by_days[key] = row
        for key in clashes:
            by_days.pop(key, None)
        self.lai_by_days = by_days

    def days(self, interval):
        """The schedule an interval label names, in days, or None if unrecognised."""
        if not interval:
            return None
        return self.interval_days.get(normalise_text(interval))

    def lai_reference(self, generic, interval):
        """Licensed maximum for this agent on this schedule, or None."""
        row = self.lai.get((generic, normalise_text(interval) if interval else ""))
        if row is None:
            days = self.days(interval)
            if days is not None:
                row = self.lai_by_days.get((generic, days))
        return row


def _f(value):
    value = (value or "").strip()
    if value == "":
        return None
    return float(value)


def load_tables(reference_dir=None):
    d = reference_dir or DEFAULT_REFERENCE_DIR
    if not os.path.isdir(d):
        raise SystemExit("reference directory not found: %s" % d)

    oral = OrderedDict()
    with open(os.path.join(d, "ap_load2026_reference_%s.csv" % TABLE_VERSION),
              newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            oral[row["generic"].strip().lower()] = {
                "bnf_max": _f(row["bnf_max_mg_day"]),
                "ddd": _f(row["who_ddd_mg_day"]),
                "published": _f(row["published_reference_mg_day"]),
                "basis": row["basis"].strip(),
                "source": row["source"].strip(),
            }

    lai = OrderedDict()
    with open(os.path.join(d, "ap_load2026_lai_%s.csv" % TABLE_VERSION),
              newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            key = (row["generic"].strip().lower(), row["interval"].strip().lower())
            lai[key] = {"max": _f(row["max_per_interval_mg"]), "source": row["source"].strip()}

    anchors = {}
    with open(os.path.join(d, "ap_load2026_clozapine_anchors.csv"),
              newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            anchors[(row["scheme"].strip().lower(), row["sex"].strip().lower(),
                     row["smoking"].strip().lower())] = float(row["target_mg_day"])

    interval_days = dict(INTERVAL_DAYS)
    intervals_csv = os.path.join(d, "ap_load2026_intervals.csv")
    if os.path.isfile(intervals_csv):
        with open(intervals_csv, newline="", encoding="utf-8") as fh:
            for row in csv.DictReader(fh):
                label = normalise_text(row["label"])
                if label:
                    interval_days[label] = float(row["days"])

    molecule, form = [], []
    with open(os.path.join(d, "ap_load2026_drug_stems.csv"),
              newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            kind = row["kind"].strip().lower()
            interval = (row["interval"] or "").strip().lower() or None
            if kind == "molecule":
                molecule.append((row["pattern"].strip().lower(),
                                 row["value"].strip().lower(), interval))
            elif kind == "form":
                value = "LAI" if row["value"].strip().lower() == "lai" else "oral"
                form.append((re.compile(row["pattern"].strip(), re.I), value, interval))
    # longest stem first: a short stem must never shadow a longer one
    molecule.sort(key=lambda t: -len(t[0]))
    return Tables(oral, lai, anchors, {"molecule": molecule, "form": form}, d,
                  interval_days)


# --- text handling --------------------------------------------------------

def normalise_text(value):
    s = "" if value is None else str(value)
    s = s.strip().lower()
    for a, b in (("á", "a"), ("é", "e"), ("í", "i"), ("ó", "o"), ("ú", "u"), ("ñ", "n")):
        s = s.replace(a, b)
    return re.sub(r"\s+", " ", s)


def match_molecule(raw, tables):
    """Prefix-anchored stem match. Returns (generic, stem, interval_hint).

    The molecule is matched at the start of the string, so amisulpride is never
    read as sulpiride. A brand name that fixes the dosing interval is then looked
    for anywhere in the string as well, so that 'Risperidone Consta' keeps the
    two-weekly schedule that 'Consta' alone would have given.
    """
    s = normalise_text(raw)
    if s in ("", "none", "n/a", "na", "nil", "ninguno", "-"):
        return None, None, None
    for stem, generic, interval in tables.molecule_stems:
        if s.startswith(stem):
            if interval is None:
                for brand, brand_generic, brand_interval in tables.brand_intervals:
                    if brand_generic == generic and brand in s:
                        return generic, stem, brand_interval
            return generic, stem, interval
    return None, None, None


def match_form(tables, *texts):
    """Scan the whole string(s) for formulation and interval keywords."""
    form = interval = None
    joined = " ".join(normalise_text(t) for t in texts if t is not None)
    for pattern, value, iv in tables.form_patterns:
        if pattern.search(joined):
            if form is None:
                form = value
            if iv and interval is None:
                interval = iv
    return form, interval


# A dose stated per administration is not a daily total, and the tool has no way
# to know how many administrations there were. Once-daily markers (od, nocte,
# mane, daily) are not here: those doses ARE the daily total.
FREQUENCY_RE = re.compile(
    r"\b(?:bd|b\.d|bid|b\.i\.d|tds|t\.d\.s|tid|t\.i\.d|qds|q\.d\.s|qid|q\.i\.d)\b"
    r"|\bq\s?\d+\s?h\b|\bcada\s+\d+\s*(?:h|horas?)\b|/\s*\d+\s*h\b"
    r"|\b(?:twice|three times|four times|dos veces|tres veces|cuatro veces)\b"
    r"|\d+\s*[-+]\s*\d+\s*[-+]\s*\d+"          # 100-0-200, a three-slot regimen
    r"|\b\d+\s*x\s*\d+|\b\d+\s*veces\b", re.I)

# Units the parser accepts, and the factor that turns them into mg.
DOSE_UNITS = {
    "": 1.0, "mg": 1.0, "mgs": 1.0, "mg.": 1.0, "miligramos": 1.0, "milligrams": 1.0,
    "milligram": 1.0, "g": 1000.0, "gr": 1000.0, "gramo": 1000.0, "gramos": 1000.0,
    "gram": 1000.0, "grams": 1000.0,
    "mcg": 0.001, "ug": 0.001, "microgram": 0.001, "micrograms": 0.001,
    "microgramo": 0.001, "microgramos": 0.001, "mcgs": 0.001,
}

DOSE_RE = re.compile(r"^(\d+(?:\.\d+)?)\s*([a-z.]*)$")


def strip_schedule_words(s, tables):
    """Remove formulation and interval vocabulary from a dose string.

    '450mg/d', '400 mg/mes' and '960/2meses' state a dose and a schedule in one
    field. The schedule is read separately by match_form; here it is removed so
    that what is left can be required to be a dose and nothing else.
    """
    if tables is not None:
        for pattern in tables.form_eaters:
            s = pattern.sub(" ", s)
    return re.sub(r"\s+", " ", s).strip(" ,;:.-/")


def parse_dose(value, tables=None):
    """Return (mg, refusal_code).

    Accepts a plain number, optionally with a unit and a schedule: 300, '300mg',
    '3 mg/d', '66,6mg/m', '960/2meses'. Refuses anything else rather than reading
    the first number it can find: '1,000 mg', '2 x 100 mg' and '300 mg bd' each
    mean something specific, and guessing at them silently changes the score.
    """
    if value is None:
        return None, NON_NUMERIC_DOSE
    if isinstance(value, (int, float)):
        if value != value or value in (float("inf"), float("-inf")):   # NaN, inf
            return None, NON_NUMERIC_DOSE
        return (float(value), None) if value > 0 else (None, DOSE_NOT_POSITIVE)

    s = normalise_text(value)
    if s == "":
        return None, NON_NUMERIC_DOSE
    if not re.search(r"\d", s):
        return None, NON_NUMERIC_DOSE
    if FREQUENCY_RE.search(s):
        return None, FREQUENCY_NOT_TOTAL
    if s.lstrip().startswith("-"):
        return None, DOSE_NOT_POSITIVE

    s = strip_schedule_words(s, tables)

    # '1,000' and '1.000' are one thousand in one convention and one in the other.
    # A leading zero ('0.500') can only be a decimal, so it is left alone.
    if re.search(r"(?<![\d.,])[1-9]\d{0,2}[.,]\d{3}(?![\d.,])", s):
        return None, AMBIGUOUS_SEPARATOR

    # A comma before one or two digits is a decimal point: 66,6 -> 66.6
    s = re.sub(r"(?<=\d),(?=\d{1,2}(?!\d))", ".", s)

    if len(re.findall(r"\d+(?:\.\d+)?", s)) > 1:
        return None, MULTIPLE_DOSES

    m = DOSE_RE.match(s)
    if not m:
        return None, NON_NUMERIC_DOSE
    unit = m.group(2).strip(".")
    if unit not in DOSE_UNITS:
        return None, UNIT_NOT_RECOGNISED
    mg = float(m.group(1)) * DOSE_UNITS[unit]
    if mg <= 0:
        return None, DOSE_NOT_POSITIVE
    return mg, None


SEX_NUMERIC_NOTE = "numeric sex code read as 1 = male, 0 = female"


def normalise_sex(value):
    """Return (sex, note). Numeric codes follow the convention 1 = male, 0 = female."""
    s = normalise_text(value)
    if s in ("m", "male", "man", "hombre", "varon", "h", "v"):
        return "male", None
    if s in ("f", "female", "woman", "mujer"):
        return "female", None
    if s in ("1", "1.0"):
        return "male", SEX_NUMERIC_NOTE
    if s in ("0", "0.0", "2", "2.0"):
        # 0 = female by the stated convention; 2 is refused as it has no agreed meaning
        return ("female", SEX_NUMERIC_NOTE) if s in ("0", "0.0") else (None, None)
    return None, None


def normalise_smoking(row):
    """Return (smoker_fraction 0..1, note). Continuous where possible."""
    cigs = row.get("cigarettes_per_day")
    if cigs not in (None, ""):
        try:
            c = float(str(cigs).replace(",", "."))
            return min(1.0, max(0.0, c / 10.0)), None
        except ValueError:
            pass
    s = normalise_text(row.get("smoking_status"))
    if s in ("1", "yes", "y", "smoker", "current", "current smoker", "fumador", "si", "true"):
        return 1.0, "binary smoking status: treated as fully induced"
    if s in ("0", "no", "n", "non-smoker", "nonsmoker", "never", "no fumador", "nofumador", "false"):
        return 0.0, "binary smoking status: treated as not induced"
    return None, None


# --- scoring --------------------------------------------------------------

def oral_reference(generic, tables):
    ref = tables.oral.get(generic)
    if ref is None:
        return None, NO_REFERENCE
    bnf, ddd = ref["bnf_max"], ref["ddd"]
    if bnf is not None and ddd is not None:
        gm = math.sqrt(bnf * ddd)
        cap = 1.5 * ddd
        return (min(gm, cap), "capped geometric mean" if gm > cap else "geometric mean")
    if bnf is not None:
        return bnf, "label maximum (no WHO DDD)"
    if ddd is not None:
        return 1.5 * ddd, "1.5 x DDD (no current licensed maximum)"
    return None, NO_REFERENCE


def clozapine_target(sex, smoke_fraction, scheme, tables):
    ns = tables.anchors[(scheme, sex, "non-smoker")]
    sm = tables.anchors[(scheme, sex, "smoker")]
    return ns + (sm - ns) * smoke_fraction


def score_row(row, tables, scheme):
    """Score one prescription row. Returns a detail dict; 'score' is None if refused."""
    out = {
        "patient_id": row.get("patient_id"),
        "raw_drug": row.get("drug"),
        "raw_dose": row.get("dose"),
        "generic": None, "stem": None, "form": None, "interval": None,
        "dose_mg": None, "reference_mg": None, "basis": None,
        "score": None, "refused": None, "note": None,
    }

    generic, stem, stem_interval = match_molecule(row.get("drug"), tables)
    if generic is None:
        out["refused"] = UNMATCHED_DRUG
        return out
    out["generic"], out["stem"] = generic, stem

    dose, dose_problem = parse_dose(row.get("dose"), tables)
    if dose_problem:
        out["refused"] = dose_problem
        return out
    out["dose_mg"] = dose

    # formulation: explicit route column wins, then brand stem, then free text
    route = normalise_text(row.get("route"))
    text_form, text_interval = match_form(tables, row.get("drug"), row.get("dose"), row.get("interval"))
    if route in ("oral", "po", "tablet", "capsule", "liquid", "oral liquid", "vo"):
        form = "oral"
    elif route in ("lai", "depot", "im", "injection", "inyectable", "depot injection"):
        form = "LAI"
    elif stem_interval:
        form = "LAI"
    else:
        form = text_form
    interval = (normalise_text(row.get("interval")) or None) or stem_interval or text_interval
    if interval and tables.days(interval) is None:
        # an interval that names no recognised schedule ('every so often') falls
        # back to one that does, if the drug name or the free text gave one
        interval = text_interval or stem_interval
    out["interval"] = interval

    if form is None:
        # unresolved: safe only if the agent has no depot formulation at all
        if generic in tables.dual_form:
            out["refused"] = AMBIGUOUS_FORM
            return out
        form = "oral"
    out["form"] = form

    if form == "LAI":
        if not interval:
            out["refused"] = LAI_INTERVAL_UNKNOWN
            return out
        ref = tables.lai_reference(generic, interval)
        if ref is None or ref["max"] is None:
            out["refused"] = LAI_NOT_IN_TABLE
            return out
        out["reference_mg"], out["basis"] = ref["max"], "licensed formulation maximum per %s" % interval
        out["score"] = dose / ref["max"] * 100.0
        return out

    if generic == "clozapine":
        sex, sex_note = normalise_sex(row.get("sex"))
        if sex is None:
            out["refused"] = MISSING_SEX
            return out
        frac, smoke_note = normalise_smoking(row)
        if frac is None:
            out["refused"] = MISSING_SMOKING
            return out
        target = clozapine_target(sex, frac, scheme, tables)
        out["reference_mg"] = target
        out["basis"] = "individualised clozapine target (%s anchors, %s)" % (scheme, sex)
        out["note"] = "; ".join(n for n in (sex_note, smoke_note) if n) or None
        out["score"] = dose / target * 100.0
        return out

    ref, basis = oral_reference(generic, tables)
    if ref is None:
        out["refused"] = basis
        return out
    out["reference_mg"], out["basis"] = ref, basis
    out["score"] = dose / ref * 100.0
    return out


def score(rows, tables, scheme="rostami"):
    details, order = [], []
    totals, scored_n, refused_n = {}, Counter(), Counter()
    for row in rows:
        d = score_row(row, tables, scheme)
        if d["reference_mg"] is not None:
            d["reference_mg"] = round(d["reference_mg"], 3)
        if d["score"] is not None:
            d["score"] = round(d["score"], 2)
        details.append(d)
        pid = d["patient_id"]
        if pid not in totals:
            totals[pid] = 0.0
            order.append(pid)
        if d["score"] is None:
            refused_n[pid] += 1
        else:
            totals[pid] += d["score"]
            scored_n[pid] += 1

    patients = []
    for pid in order:
        patients.append(OrderedDict([
            ("patient_id", pid),
            ("AP_Load2026", None if scored_n[pid] == 0 else round(totals[pid], 1)),
            ("drugs_scored", scored_n[pid]),
            ("rows_refused", refused_n[pid]),
            ("complete", "yes" if refused_n[pid] == 0 else "NO"),
            ("clozapine_anchors", scheme),
            ("reference_table", TABLE_VERSION),
        ]))

    report = OrderedDict([
        ("ap_load2026_version", VERSION),
        ("reference_table", TABLE_VERSION),
        ("reference_dir", tables.source_dir),
        ("clozapine_anchors", scheme),
        ("patients", len(order)),
        ("patients_complete", sum(1 for p in patients if p["complete"] == "yes")),
        ("drug_rows", len(details)),
        ("drug_rows_scored", sum(1 for d in details if d["score"] is not None)),
        ("drug_rows_refused", sum(1 for d in details if d["score"] is None)),
        ("refusals_by_reason", Counter(d["refused"] for d in details if d["refused"])),
        ("unmatched_names", Counter(str(d["raw_drug"]) for d in details
                                    if d["refused"] == UNMATCHED_DRUG)),
    ])
    return patients, details, report


def format_report(report):
    lines = ["AP_Load2026 %s   reference table %s   clozapine anchors: %s"
             % (report["ap_load2026_version"], report["reference_table"], report["clozapine_anchors"]),
             "reference directory: %s" % report["reference_dir"],
             "patients: %d (%d complete, %d with at least one refused row)"
             % (report["patients"], report["patients_complete"],
                report["patients"] - report["patients_complete"]),
             "drug rows: %d scored, %d refused"
             % (report["drug_rows_scored"], report["drug_rows_refused"])]
    if report["refusals_by_reason"]:
        lines.append("refusals:")
        for reason, n in report["refusals_by_reason"].most_common():
            lines.append("   %-34s %4d   %s" % (reason, n, REFUSAL_HELP.get(reason, "")))
    if report["unmatched_names"]:
        lines.append("unmatched drug names:")
        for name, n in report["unmatched_names"].most_common():
            lines.append("   %-34s %4d" % (name[:34], n))
    return "\n".join(lines)


PATIENT_FIELDS = ["patient_id", "AP_Load2026", "drugs_scored", "rows_refused",
                  "complete", "clozapine_anchors", "reference_table"]
DETAIL_FIELDS = ["patient_id", "raw_drug", "raw_dose", "generic", "stem", "form",
                 "interval", "dose_mg", "reference_mg", "basis", "score",
                 "refused", "note"]


def write_csv(path, rows, fieldnames=None):
    """Write a CSV, header included even when there are no rows.

    An empty file is a result: 'nothing was refused' must be distinguishable from
    'the run did not get that far', and a file left unwritten would leave the
    previous run's output in place to be read as this one's.
    """
    fieldnames = fieldnames or (list(rows[0].keys()) if rows else None)
    if fieldnames is None:
        return
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Compute AP_Load2026 from a long-format prescription file.")
    ap.add_argument("input_csv")
    ap.add_argument("output_csv")
    ap.add_argument("--detail-csv", default=None, help="per-drug scoring detail (recommended)")
    ap.add_argument("--review-csv", default=None, help="refused rows only, for manual correction")
    ap.add_argument("--anchors", choices=["rostami", "reeves"], default="rostami")
    ap.add_argument("--reference-dir", default=None, help="a local copy of the reference tables")
    args = ap.parse_args(argv)

    tables = load_tables(args.reference_dir)

    with open(args.input_csv, newline="", encoding="utf-8-sig") as fh:
        rows = list(csv.DictReader(fh))

    patients, details, report = score(rows, tables, args.anchors)
    write_csv(args.output_csv, patients, PATIENT_FIELDS)
    if args.detail_csv:
        write_csv(args.detail_csv, details, DETAIL_FIELDS)
    if args.review_csv:
        write_csv(args.review_csv, [d for d in details if d["score"] is None], DETAIL_FIELDS)
    print(format_report(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
