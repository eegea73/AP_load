#!/usr/bin/env python3
"""A dose that could mean two things must be refused, not read as the first number.

Each row of examples/tricky_doses.csv is a way a prescription is really written.
The ones that can be resolved must score exactly; the ones that cannot must be
refused with the reason that says why, because a dose silently read as 1 mg
instead of 1,000 mg changes a cohort's mean and never announces itself.
"""
import csv, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "python"))
import ap_load2026 as ap

EXPECTED = {
    # id     refusal code (None = must score)   expected score
    "t01": (ap.AMBIGUOUS_SEPARATOR, None),      # 1,000 mg: one thousand, or one?
    "t02": (ap.FREQUENCY_NOT_TOTAL, None),      # 300 mg bd is 600 mg a day
    "t03": (ap.FREQUENCY_NOT_TOTAL, None),      # 2 x 100 mg is 200 mg a day
    "t04": (None, 4.2),                         # 500 microgram = 0.5 mg of 12 mg
    "t05": (None, 83.3),                        # 1 g = 1000 mg of 1200 mg
    "t06": (ap.DOSE_NOT_POSITIVE, None),
    "t07": (ap.MULTIPLE_DOSES, None),           # two doses in one field
    "t08": (None, 100.0),                       # Consta found after the generic
    "t09": (None, 50.0),                        # 'monthly' finds the 4-weekly row
    "t10": (None, 100.0),                       # '4-weekly' finds the monthly row
    "t11": (ap.UNIT_NOT_RECOGNISED, None),      # ml is a volume, not a dose
    "t12": (None, 76.2),                        # an ordinary dose still scores
    "t13": (None, 66.7),                        # '90 days' is the 3-monthly schedule
    "t14": (ap.DOSE_NOT_POSITIVE, None),
}

tables = ap.load_tables()
with open(os.path.join(ROOT, "examples", "tricky_doses.csv"),
          newline="", encoding="utf-8-sig") as fh:
    rows = list(csv.DictReader(fh))
patients, details, report = ap.score(rows, tables, "rostami")
by_id = {d["patient_id"]: d for d in details}

fails = []
for pid in sorted(EXPECTED):
    want_refusal, want_score = EXPECTED[pid]
    d = by_id[pid]
    if want_refusal is None:
        ok = d["score"] is not None and abs(d["score"] - want_score) <= 0.15
        got = d["refused"] if d["score"] is None else "%.1f" % d["score"]
        print("  %-5s %-22s -> %-12s expected %.1f   %s"
              % (pid, str(d["raw_dose"])[:22], got, want_score, "ok" if ok else "MISMATCH"))
    else:
        ok = d["refused"] == want_refusal
        got = d["refused"] or "SCORED %.1f" % d["score"]
        print("  %-5s %-22s -> %-12s expected %s   %s"
              % (pid, str(d["raw_dose"])[:22], got[:12], want_refusal, "ok" if ok else "MISMATCH"))
    if not ok:
        fails.append(pid)

print()
if fails:
    print("FAILURES: %s" % ", ".join(fails))
    raise SystemExit(1)
print("Ambiguous doses refused, resolvable ones scored, interval synonyms matched.")
