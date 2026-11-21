#!/usr/bin/env python3
"""The tool must fail safely: every ambiguous row refused, with the right reason."""

import csv, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "python"))
import ap_load2026 as ap

EXPECTED_REFUSALS = {
    "bad01": ap.AMBIGUOUS_FORM,  # aripiprazole 400: oral daily or monthly depot?
    "bad02": ap.UNMATCHED_DRUG,  # not an antipsychotic
    "bad03": ap.MISSING_SEX,  # clozapine without sex
    "bad04": ap.LAI_INTERVAL_UNKNOWN,  # depot without an interval
    "bad05": ap.MISSING_SMOKING,  # clozapine without smoking information
    "bad06": ap.NON_NUMERIC_DOSE,  # "twice daily" is not a dose
}
EXPECTED_SCORED = {
    "ok01": 92.9,
    "ok02": 122.6,
    "ok03": 66.7,
    "ok04": 100.0,
    "ok05": 54.8,
    "ok06": 88.9,
}

tables = ap.load_tables()
with open(
    os.path.join(ROOT, "examples", "messy_example.csv"), newline="", encoding="utf-8"
) as fh:
    rows = list(csv.DictReader(fh))
patients, details, report = ap.score(rows, tables, "rostami")
by_id = {d["patient_id"]: d for d in details}

fails = []
print("resolved:")
for pid, exp in sorted(EXPECTED_SCORED.items()):
    d = by_id[pid]
    got = None if d["score"] is None else round(d["score"], 1)
    ok = got is not None and abs(got - exp) <= 0.15
    print(
        "  %-6s %-30s -> %-16s %-9s %8s  expected %6.1f  %s"
        % (
            pid,
            str(d["raw_drug"])[:29],
            d["generic"],
            d["form"] or "",
            "%.1f" % got if got is not None else d["refused"],
            exp,
            "ok" if ok else "MISMATCH",
        )
    )
    if not ok:
        fails.append((pid, exp, got or d["refused"]))

print("\nrefused:")
for pid, exp in sorted(EXPECTED_REFUSALS.items()):
    d = by_id[pid]
    ok = d["refused"] == exp
    print(
        "  %-6s %-30s -> %-34s %s"
        % (
            pid,
            str(d["raw_drug"])[:29],
            d["refused"] or "SCORED (%.1f)" % d["score"],
            "ok" if ok else "EXPECTED " + exp,
        )
    )
    if not ok:
        fails.append((pid, exp, d["refused"]))

print()
print(ap.format_report(report))
if fails:
    print("\nFAILURES: %d" % len(fails))
    raise SystemExit(1)
print("\nAll refusal behaviour as specified.")
