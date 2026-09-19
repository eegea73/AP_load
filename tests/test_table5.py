#!/usr/bin/env python3
"""The sixteen illustrative regimens of manuscript Table 5 must reproduce exactly."""
import csv, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "python"))
from ap_load2026 import load_tables, score

tables = load_tables()
with open(os.path.join(ROOT, "examples", "table5_regimens.csv"), newline="", encoding="utf-8") as fh:
    rows = list(csv.DictReader(fh))
with open(os.path.join(ROOT, "examples", "table5_expected.csv"), newline="", encoding="utf-8") as fh:
    expected = {r["patient_id"]: (int(r["AP_Load2026_rounded"]), r["regimen"]) for r in csv.DictReader(fh)}

patients, details, report = score(rows, tables, "rostami")
got = {p["patient_id"]: p for p in patients}

fails = []

for pid, (exp, label) in expected.items():
    p = got.get(pid)
    if p is None or p["AP_Load2026"] is None:
        fails.append((pid, exp, None, label)); continue
    if p["rows_refused"]:
        fails.append((pid, exp, "refused rows", label)); continue
    val = p["AP_Load2026"]
    ok = round(val) == exp
    print("%-8s %-52s %8.1f  Table 5: %3d  %s" % (pid, label, val, exp, "ok" if ok else "MISMATCH"))
    if not ok:
        fails.append((pid, exp, val, label))

print()
if fails:
    for pid, exp, got_v, label in fails:
        print("FAIL %s: expected %s, got %s (%s)" % (pid, exp, got_v, label))
    raise SystemExit(1)
print("All 16 Table 5 regimens reproduced. Rows refused: %d" % report["drug_rows_refused"])
