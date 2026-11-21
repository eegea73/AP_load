#!/usr/bin/env python3
"""Python and R must agree to the decimal on both fixtures."""

import csv, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "python"))
import ap_load2026 as ap

if shutil.which("Rscript") is None:
    print(
        "R is not installed here, so Python and R cannot be compared; "
        "the other tests still apply."
    )
    raise SystemExit(0)

tables = ap.load_tables(os.path.join(ROOT, "reference"))
fails = 0
for fixture in ("table5_regimens.csv", "messy_example.csv", "tricky_doses.csv"):
    src = os.path.join(ROOT, "examples", fixture)
    with open(src, newline="", encoding="utf-8-sig") as fh:
        rows = list(csv.DictReader(fh))
    py_pat, py_det, _ = ap.score(rows, tables, "rostami")

    tmp = tempfile.mkdtemp()
    out, det = os.path.join(tmp, "p.csv"), os.path.join(tmp, "d.csv")
    subprocess.run(
        [
            "Rscript",
            os.path.join(ROOT, "r", "ap_load2026.R"),
            src,
            out,
            det,
            "--reference-dir",
            os.path.join(ROOT, "reference"),
        ],
        check=True,
        capture_output=True,
    )
    with open(out, newline="", encoding="utf-8") as fh:
        r_pat = {r["patient_id"]: r for r in csv.DictReader(fh)}
    with open(det, newline="", encoding="utf-8") as fh:
        r_det = list(csv.DictReader(fh))

    print("%s: %d patients, %d rows" % (fixture, len(py_pat), len(py_det)))
    for p in py_pat:
        rr = r_pat.get(p["patient_id"])
        pv = "" if p["AP_Load2026"] is None else "%.1f" % p["AP_Load2026"]
        rv = (rr or {}).get("AP_Load2026", "")
        rv = "" if rv in ("", "NA") else "%.1f" % float(rv)
        if pv != rv:
            print(
                "   SCORE MISMATCH %s: python %s, R %s"
                % (p["patient_id"], pv or "NA", rv or "NA")
            )
            fails += 1
    for a, b in zip(py_det, r_det):
        pa = a["refused"] or ""
        rb = "" if b["refused"] in ("", "NA") else b["refused"]
        if pa != rb:
            print(
                "   REFUSAL MISMATCH %s/%s: python %r, R %r"
                % (a["patient_id"], a["raw_drug"], pa, rb)
            )
            fails += 1
print()
if fails:
    print("FAILURES: %d" % fails)
    raise SystemExit(1)
print("Python and R agree on every patient score and every refusal.")
