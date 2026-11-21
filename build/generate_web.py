#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Write the reference tables into the browser calculator, from reference/*.csv.

The browser calculator cannot read the CSVs at run time, so the numbers are
written into it here - the same arrangement as the SPSS syntax, and for the same
reason: reference/ is the single source of truth, and a table typed out by hand
in a second place is a table that will disagree with the first one eventually.

Rewrites the block between BEGIN GENERATED TABLES and END GENERATED TABLES in
web/apload.js, then copies the whole of apload.js into the <script> element of
the single-file web/apload-squarespace.html, so that the two builds of the
calculator cannot disagree about anything at all.

    python3 build/generate_web.py

Display names are the one thing this script decides rather than reads: the CSVs
hold generic names in lower case, and the calculator shows them capitalised, with
the ester added for the depots that are prescribed under it. Nothing in that map
affects a score.
"""

import csv
import math
import os
import re
from typing import Dict, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REF = os.path.join(ROOT, "reference")
TABLE_VERSION = "2026-11"

BEGIN = "/* BEGIN GENERATED TABLES"
END = "/* END GENERATED TABLES */"

# Cosmetic only: how a generic name is displayed, where capitalising it is not
# enough. Depots are prescribed under the ester, so the ester is shown.
DISPLAY = {
    "xanomeline-trospium": "Xanomeline-trospium",
}
LAI_ESTER = {
    "haloperidol": "Haloperidol decanoate",
    "flupentixol": "Flupentixol decanoate",
    "zuclopenthixol": "Zuclopenthixol decanoate",
    "fluphenazine": "Fluphenazine decanoate",
}

# Days used ONLY for the DDD/day comparison column. The WHO derives a depot's
# defined daily dose over a calendar month, so 400 mg monthly aripiprazole is
# 13.3 mg/day; using 28 days here would make a dose at the DDD read as 1.07 DDD.
# The reference table lookup does not use these numbers - it uses the dosing
# schedule in reference/ap_load2026_intervals.csv.
DDD_DAYS = {
    "weekly": 7,
    "2-weekly": 14,
    "4-weekly": 28,
    "monthly": 30,
    "2-monthly": 60,
    "3-monthly": 90,
    "6-monthly": 180,
}

# A basis string the calculator works out for itself from the two numbers; any
# other basis carries an explanation worth showing beside the drug.
STANDARD_BASIS = {
    "1.5 x DDD (cap)",
    "geometric mean",
    "geometric mean (= label max)",
    "label max (no WHO DDD)",
    "individualised target (see anchors)",
}


def read(name: str) -> List[Dict[str, str]]:
    with open(os.path.join(REF, name), newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def num(v: Optional[str]) -> Optional[float]:
    v = (v or "").strip()
    return float(v) if v else None


def js_num(v: Optional[float]) -> str:
    if v is None:
        return "null"
    return "%g" % v


def display_name(generic: str) -> str:
    return DISPLAY.get(generic, generic[:1].upper() + generic[1:])


def computed_basis(bnf: Optional[float], ddd: Optional[float]) -> str:
    """The basis label the calculator works out for itself from the two numbers."""
    if ddd is None:
        return "Label maximum (no WHO DDD)"
    if bnf is None:
        return "1.5 x DDD (no current UK maximum)"
    return "1.5 x DDD (cap)" if math.sqrt(bnf * ddd) > 1.5 * ddd else "Geometric mean"


def flatten(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def display_note(
    basis: str, bnf: Optional[float], ddd: Optional[float]
) -> Optional[str]:
    """The part of a basis string worth showing beside the drug name, or None.

    The Basis column already states the formula, so a note repeating it is noise:
    'fluphenazine - oral form discontinued in the UK' is worth a line, while
    '1.5 x DDD (no current UK max)' beside a Basis of '1.5 × DDD (no current UK
    maximum)' says the same thing twice.
    """
    if basis in STANDARD_BASIS:
        return None
    depth, cut = 0, None
    for i, ch in enumerate(basis):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        elif ch == ";" and depth == 0:
            cut = i
    note = basis[cut + 1 :].strip() if cut is not None else None
    if not note:
        m = re.search(r"\(([^()]*)\)\s*$", basis)
        note = m.group(1).strip() if m else basis.strip()
    if flatten(note) in flatten(computed_basis(bnf, ddd)):
        return None
    return note


def build_block() -> str:
    oral_rows = read("ap_load2026_reference_%s.csv" % TABLE_VERSION)
    lai_rows = read("ap_load2026_lai_%s.csv" % TABLE_VERSION)
    anchor_rows = read("ap_load2026_clozapine_anchors.csv")

    lines: List[str] = []
    w = lines.append

    w("  /* BEGIN GENERATED TABLES - do not edit by hand.")
    w("     Written from reference/*.csv by:  python3 build/generate_web.py")
    w("     These are the same tables the Python, R and SPSS implementations read.")
    w("     Display names are cosmetic and come from the generator; every number")
    w("     comes from the reference CSVs. */")
    w("")
    w(
        "  // bnfMax: UK BNF 2026 maximum, or national label maximum (mg/day). null = none current."
    )
    w("  // ddd: WHO Defined Daily Dose (mg/day). null = no assigned DDD.")
    w("  var ORAL = [")
    entries = []
    cloz: Optional[Tuple[Optional[float], Optional[float]]] = None
    for r in oral_rows:
        generic = r["generic"].strip().lower()
        basis = r["basis"].strip()
        bits = [
            "name: '%s'" % display_name(generic),
            "bnfMax: %s" % js_num(num(r["bnf_max_mg_day"])),
            "ddd: %s" % js_num(num(r["who_ddd_mg_day"])),
        ]
        if generic == "clozapine":
            bits.append("individualised: true")
            cloz = (num(r["bnf_max_mg_day"]), num(r["who_ddd_mg_day"]))
        note = display_note(basis, num(r["bnf_max_mg_day"]), num(r["who_ddd_mg_day"]))
        if note:
            bits.append("note: '%s'" % note.replace("'", "\\'"))
        entries.append("    { %s }" % ", ".join(bits))
    w(",\n".join(sorted(entries, key=lambda s: s.lower())))
    w("  ];")
    w("")
    w("  // maxPerInterval: licensed maximum for one injection interval (mg).")
    w("  // depotDDD: WHO defined daily dose for the depot (mg/day); dddDays is the")
    w("  // calendar length WHO derives it over, and is used only for that column.")
    w("  var LAI = [")
    entries = []
    for r in lai_rows:
        generic = r["generic"].strip().lower()
        interval = r["interval"].strip().lower()
        name = LAI_ESTER.get(generic, display_name(generic))
        entries.append(
            "    { name: '%s', interval: '%s', dddDays: %d, maxPerInterval: %s, depotDDD: %s }"
            % (
                name,
                interval,
                DDD_DAYS[interval],
                js_num(num(r["max_per_interval_mg"])),
                js_num(num(r["who_depot_ddd_mg_day"])),
            )
        )
    w(",\n".join(entries))
    w("  ];")
    w("")
    w(
        "  // Individualised clozapine target doses (mg/day) for a plasma clozapine of 0.35 mg/L."
    )
    anchors = {}
    for r in anchor_rows:
        anchors[
            (
                r["scheme"].strip().lower(),
                r["sex"].strip().lower(),
                r["smoking"].strip().lower(),
            )
        ] = float(r["target_mg_day"])
    labels = {
        "rostami": "Rostami-Hodjegan-derived (standard)",
        "reeves": "Reeves-derived",
    }
    keys = {"rostami": "rh", "reeves": "reeves"}
    w("  var CLOZ_ANCHORS = {")
    rows = []
    for scheme in ("rostami", "reeves"):
        rows.append(
            "    %-7s { label: '%s', F: { ns: %g, s: %g }, M: { ns: %g, s: %g } }"
            % (
                keys[scheme] + ":",
                labels[scheme],
                anchors[(scheme, "female", "non-smoker")],
                anchors[(scheme, "female", "smoker")],
                anchors[(scheme, "male", "non-smoker")],
                anchors[(scheme, "male", "smoker")],
            )
        )
    w(",\n".join(rows))
    w("  };")
    if cloz is None or cloz[0] is None or cloz[1] is None:
        raise SystemExit(
            "clozapine needs a BNF maximum and a DDD in the reference table"
        )
    w("  var CLOZ_BNF_MAX = %g;" % cloz[0])
    w("  var CLOZ_DDD = %g;" % cloz[1])
    w(
        "  var SATURATION_CIGS = 10;   // CYP1A2 induction saturates at ~10 cigarettes/day"
    )
    w("")
    w("  /* END GENERATED TABLES */")
    return "\n".join(lines)


def splice(path: str, block: str) -> str:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    start = text.find(BEGIN)
    end = text.find(END)
    if start < 0 or end < 0:
        raise SystemExit("markers not found in %s" % path)
    # keep the indentation the block starts on
    line_start = text.rfind("\n", 0, start) + 1
    updated = text[:line_start] + block + "\n" + text[end + len(END) + 1 :]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(updated)
    return updated


def sync_squarespace() -> None:
    """Put the whole of apload.js inside the single-file build's <script>."""
    js_path = os.path.join(ROOT, "web", "apload.js")
    sq_path = os.path.join(ROOT, "web", "apload-squarespace.html")
    with open(js_path, encoding="utf-8") as fh:
        js = fh.read().strip("\n")
    with open(sq_path, encoding="utf-8") as fh:
        html = fh.read()
    new, n = re.subn(
        r"(<script>\n).*?(\n</script>)",
        lambda m: m.group(1) + js + m.group(2),
        html,
        count=1,
        flags=re.S,
    )
    if not n:
        raise SystemExit("no <script> element found in web/apload-squarespace.html")
    with open(sq_path, "w", encoding="utf-8") as fh:
        fh.write(new)


def main() -> None:
    js_path = os.path.join(ROOT, "web", "apload.js")
    if not os.path.isfile(js_path):
        raise SystemExit(
            "web/apload.js not found. It is the template the tables are written into,\n"
            "so it must be present: check that the whole web/ folder was cloned."
        )
    splice(os.path.join(ROOT, "web", "apload.js"), build_block())
    print("wrote tables into web/apload.js")
    sync_squarespace()
    print("copied web/apload.js into web/apload-squarespace.html")


if __name__ == "__main__":
    main()
