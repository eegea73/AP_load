#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate spss/ap_load2026.sps from the reference CSVs.

The SPSS syntax cannot read the reference tables at run time, so the numbers are
written into it here. This script is the reason the three implementations cannot
drift apart: Python and R read the CSVs directly, and SPSS is generated from them.

Re-run after any change to reference/:

    python3 build/generate_spss.py
"""

import csv
import math
import os
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REF = os.path.join(ROOT, "reference")
OUT = os.path.join(ROOT, "spss", "ap_load2026.sps")
TABLE_VERSION = "2026-09"
SLOTS = 4


def read(name):
    with open(os.path.join(REF, name), newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def num(v):
    v = (v or "").strip()
    return float(v) if v else None


def oral_reference(bnf, ddd):
    if bnf is not None and ddd is not None:
        gm, cap = math.sqrt(bnf * ddd), 1.5 * ddd
        return (min(gm, cap), "capped geometric mean" if gm > cap else "geometric mean")
    if bnf is not None:
        return bnf, "label maximum (no WHO DDD)"
    if ddd is not None:
        return 1.5 * ddd, "1.5 x DDD (no current licensed maximum)"
    return None, None


def render():
    """Build the whole .sps as text, so a test can check the committed file."""
    oral_rows = read("ap_load2026_reference_%s.csv" % TABLE_VERSION)
    lai_rows = read("ap_load2026_lai_%s.csv" % TABLE_VERSION)
    anchor_rows = read("ap_load2026_clozapine_anchors.csv")
    stem_rows = read("ap_load2026_drug_stems.csv")

    oral = OrderedDict()
    for r in oral_rows:
        g = r["generic"].strip().lower()
        if g == "clozapine":
            continue
        ref, basis = oral_reference(num(r["bnf_max_mg_day"]), num(r["who_ddd_mg_day"]))
        if ref is not None:
            oral[g] = (ref, basis)

    lai = [(r["generic"].strip().lower(), r["interval"].strip().lower(),
            num(r["max_per_interval_mg"])) for r in lai_rows]
    lai = [x for x in lai if x[2] is not None]
    dual = sorted(set(g for g, _i, _m in lai))

    anchors = {}
    for r in anchor_rows:
        anchors[(r["scheme"].strip().lower(), r["sex"].strip().lower(),
                 r["smoking"].strip().lower())] = float(r["target_mg_day"])

    stems = [(r["pattern"].strip().lower(), r["value"].strip().lower(),
              (r["interval"] or "").strip().lower())
             for r in stem_rows if r["kind"].strip().lower() == "molecule"]
    stems.sort(key=lambda t: -len(t[0]))

    # interval vocabulary: label -> days. Labels naming the same schedule share a
    # number, which is what the depot table is looked up under, so 'monthly' and
    # '4-weekly' find the same row.
    interval_days = {"weekly": 7.0, "2-weekly": 14.0, "4-weekly": 28.0, "monthly": 28.0,
                     "2-monthly": 56.0, "3-monthly": 84.0, "6-monthly": 168.0}
    iv_path = os.path.join(REF, "ap_load2026_intervals.csv")
    if os.path.isfile(iv_path):
        for r in read("ap_load2026_intervals.csv"):
            label = r["label"].strip().lower()
            if label:
                interval_days[label] = float(r["days"])

    # (generic, days) -> maximum, where the table gives only one maximum for that
    # schedule; anything ambiguous stays on exact-label matching
    lai_by_days, clashes = OrderedDict(), set()
    for generic, interval, mx in lai:
        days = interval_days.get(interval)
        if days is None:
            continue
        key = (generic, days)
        if key in lai_by_days and lai_by_days[key][0] != mx:
            clashes.add(key)
        lai_by_days[key] = (mx, interval)
    for key in clashes:
        lai_by_days.pop(key, None)

    L = []
    w = L.append

    w("* Encoding: UTF-8.")
    w("*" + " " + "-" * 76 + ".")
    w("* AP_Load2026 - the Antipsychotic Dose Load.")
    w("* Fernandez-Egea E, Krishnadas R, Jenkins C, Patel R, Cardinal RN, Wolpe N (2026).")
    w("* The Antipsychotic Dose Load (AP_Load2026): a normalised prescribed-dose index")
    w("* for schizophrenia research. [citation to be completed on acceptance].")
    w("* Reference table %s. GENERATED FILE - do not edit by hand." % TABLE_VERSION)
    w("* Regenerate with:  python3 build/generate_spss.py")
    w("*" + " " + "-" * 76 + ".")
    w("*")
    w("* Expects one row per PATIENT (wide), with up to %d antipsychotic slots:" % SLOTS)
    w("*")
    w("*   patient_id   any type")
    w("*   sex          NUMERIC, 1 = male, 0 = female")
    w("*   cigs_per_day NUMERIC, cigarettes per day (0 for a non-smoker)")
    w("*   AP_1 .. AP_%d          STRING, drug name (generic or brand, English or Spanish)" % SLOTS)
    w("*   AP_1_dose .. AP_%d_dose      NUMERIC, mg per day (oral) or mg per interval (depot)" % SLOTS)
    w("*   AP_1_route .. AP_%d_route    STRING, 'oral' or 'LAI'   (optional)" % SLOTS)
    w("*   AP_1_interval .. AP_%d_interval  STRING, e.g. 'monthly' (depots only)" % SLOTS)
    w("*")
    w("* Unlike the Python and R implementations, this syntax does NOT read free text")
    w("* doses. Doses must already be numeric. Anything that cannot be resolved without")
    w("* guessing is flagged in apl_flag and left out of the score - never scored as 0.")
    w("*")
    w("* apl_flag:  0 scored   1 drug not recognised   2 dose missing or not numeric")
    w("*            3 oral or depot could not be told apart   4 depot interval missing")
    w("*            5 sex missing (clozapine)   6 smoking missing (clozapine)")
    w("*" + " " + "-" * 76 + ".")
    w("*")
    w("* If your data has no route/interval columns, create empty ones first:")
    w("*   STRING %s (A8)" % " ".join("AP_%d_route" % i for i in range(1, SLOTS + 1)))
    w("*          %s (A12)." % " ".join("AP_%d_interval" % i for i in range(1, SLOTS + 1)))
    w("* An oral-only agent (clozapine, quetiapine, amisulpride) then still scores;")
    w("* an agent with both forms is flagged rather than guessed.")
    w("*" + " " + "-" * 76 + ".")
    w("")
    w("* ---- 1. restructure the slots to one row per prescription --------------------.")
    w("")
    w("DATASET COPY apl_work.")
    w("DATASET ACTIVATE apl_work.")
    w("")
    w("VARSTOCASES")
    w("  /MAKE apl_drug FROM %s" % " ".join("AP_%d" % i for i in range(1, SLOTS + 1)))
    w("  /MAKE apl_dose FROM %s" % " ".join("AP_%d_dose" % i for i in range(1, SLOTS + 1)))
    w("  /MAKE apl_route FROM %s" % " ".join("AP_%d_route" % i for i in range(1, SLOTS + 1)))
    w("  /MAKE apl_interval FROM %s" % " ".join("AP_%d_interval" % i for i in range(1, SLOTS + 1)))
    w("  /INDEX = apl_slot")
    w("  /KEEP = patient_id sex cigs_per_day")
    w("  /NULL = DROP.")
    w("")
    w("STRING apl_nm (A64) apl_gen (A24) apl_stem (A14) apl_form (A4) apl_int (A24)")
    w("       apl_basis (A48).")
    w("NUMERIC apl_ref (F10.4) apl_score (F10.4) apl_flag (F1.0) apl_frac (F6.4).")
    w("COMPUTE apl_flag = 0.")
    w("COMPUTE apl_nm = LOWER(LTRIM(RTRIM(apl_drug))).")
    w("COMPUTE apl_gen = ''.")
    w("COMPUTE apl_basis = ''.")
    w("COMPUTE apl_form = LOWER(LTRIM(RTRIM(apl_route))).")
    w("COMPUTE apl_int = LOWER(LTRIM(RTRIM(apl_interval))).")
    w("")
    w("* ---- 2. drug names, matched on stems anchored at the start of the string -----.")
    w("* Longest stem first, so a short stem can never shadow a longer one.")
    w("* Matching is by prefix, NOT by INDEX(): INDEX() would read amisulpride as")
    w("* sulpiride. To support another country, add a branch here and to the CSV.")
    w("")
    first = True
    for stem, generic, interval in stems:
        kw = "DO IF" if first else "ELSE IF"
        pad = "" if first else "+"
        w("%s%s (SUBSTR(apl_nm, 1, %d) = '%s')." % (pad, kw, len(stem), stem))
        w("+  COMPUTE apl_gen = '%s'." % generic)
        w("+  COMPUTE apl_stem = '%s'." % stem)
        if interval:
            w("+  COMPUTE apl_form = 'lai'.")
            w("+  IF (LTRIM(RTRIM(apl_int)) = '') apl_int = '%s'." % interval)
        first = False
    w("+ELSE.")
    w("+  COMPUTE apl_flag = 1.")
    w("END IF.")
    w("")
    w("* ---- 3. dose, formulation and sex --------------------------------------------.")
    w("")
    w("IF (apl_flag = 0 AND MISSING(apl_dose)) apl_flag = 2.")
    w("IF (apl_flag = 0 AND apl_dose <= 0) apl_flag = 2.")
    w("")
    w("* an explicit route wins; a depot brand has already set one above.")
    w("IF (apl_form = 'po' OR apl_form = 'oral') apl_form = 'oral'.")
    w("IF (apl_form = 'im' OR apl_form = 'depot' OR apl_form = 'lai') apl_form = 'lai'.")
    w("")
    w("* an agent with both an oral and a depot form cannot be scored without a route.")
    w("DO IF (apl_flag = 0 AND apl_form <> 'oral' AND apl_form <> 'lai').")
    dual_test = " OR ".join("apl_gen = '%s'" % g for g in dual)
    w("+  DO IF (%s)." % dual_test)
    w("+    COMPUTE apl_flag = 3.")
    w("+  ELSE.")
    w("+    COMPUTE apl_form = 'oral'.")
    w("+  END IF.")
    w("END IF.")
    w("")
    w("IF (apl_flag = 0 AND apl_form = 'lai' AND LTRIM(RTRIM(apl_int)) = '') apl_flag = 4.")
    w("")
    w("* ---- 3b. the dosing schedule, in days -----------------------------------------.")
    w("* 'monthly' and '4-weekly' name one schedule, and a prescriber may write")
    w("* either; the depot table below is looked up on the number of days, so both")
    w("* find the same row. The vocabulary is reference/ap_load2026_intervals.csv -")
    w("* add local spellings there and regenerate.")
    w("")
    w("NUMERIC apl_days (F6.1).")
    w("COMPUTE apl_days = $SYSMIS.")
    for label in sorted(interval_days, key=lambda s: (-len(s), s)):
        w("IF (apl_int = '%s') apl_days = %g." % (label, interval_days[label]))
    w("IF (apl_flag = 0 AND apl_form = 'lai' AND MISSING(apl_days)) apl_flag = 4.")
    w("")
    w("* ---- 4. reference doses ------------------------------------------------------.")
    w("")
    w("* 4a. clozapine: target individualised for sex and cigarettes per day.")
    ros_m_ns = anchors[("rostami", "male", "non-smoker")]
    ros_m_s = anchors[("rostami", "male", "smoker")]
    ros_f_ns = anchors[("rostami", "female", "non-smoker")]
    ros_f_s = anchors[("rostami", "female", "smoker")]
    w("* Rostami-Hodjegan-derived anchors (the reference configuration).")
    w("* For the Reeves-derived configuration substitute: male %g/%g, female %g/%g."
      % (anchors[("reeves", "male", "non-smoker")], anchors[("reeves", "male", "smoker")],
         anchors[("reeves", "female", "non-smoker")], anchors[("reeves", "female", "smoker")]))
    w("DO IF (apl_flag = 0 AND apl_gen = 'clozapine').")
    w("+  DO IF (MISSING(sex) OR (sex <> 0 AND sex <> 1)).")
    w("+    COMPUTE apl_flag = 5.")
    w("+  ELSE IF (MISSING(cigs_per_day)).")
    w("+    COMPUTE apl_flag = 6.")
    w("+  ELSE.")
    w("+    COMPUTE apl_frac = MIN(1, MAX(0, cigs_per_day / 10)).")
    w("+    DO IF (sex = 1).")
    w("+      COMPUTE apl_ref = %g + (%g - %g) * apl_frac." % (ros_m_ns, ros_m_s, ros_m_ns))
    w("+      COMPUTE apl_basis = 'individualised clozapine target (male)'.")
    w("+    ELSE.")
    w("+      COMPUTE apl_ref = %g + (%g - %g) * apl_frac." % (ros_f_ns, ros_f_s, ros_f_ns))
    w("+      COMPUTE apl_basis = 'individualised clozapine target (female)'.")
    w("+    END IF.")
    w("+  END IF.")
    w("END IF.")
    w("")
    w("* 4b. other oral agents: geometric mean of licensed maximum and WHO DDD,")
    w("*     capped at 1.5 x DDD. Values computed from the reference table.")
    w("DO IF (apl_flag = 0 AND apl_form = 'oral' AND apl_gen <> 'clozapine').")
    first = True
    for generic, (ref, basis) in oral.items():
        kw = "DO IF" if first else "ELSE IF"
        w("+  %s (apl_gen = '%s')." % (kw, generic))
        w("+    COMPUTE apl_ref = %.6f." % ref)
        w("+    COMPUTE apl_basis = '%s'." % basis)
        first = False
    w("+  ELSE.")
    w("+    COMPUTE apl_flag = 1.")
    w("+  END IF.")
    w("END IF.")
    w("")
    w("* 4c. long-acting injectables: licensed maximum for the same interval.")
    w("* Matched on the schedule in days rather than on the label, so a depot")
    w("* filed as 4-weekly is found by 'monthly' and the reverse.")
    w("DO IF (apl_flag = 0 AND apl_form = 'lai').")
    first = True
    for (generic, days), (mx, interval) in lai_by_days.items():
        kw = "DO IF" if first else "ELSE IF"
        w("+  %s (apl_gen = '%s' AND apl_days = %g)." % (kw, generic, days))
        w("+    COMPUTE apl_ref = %.6f." % mx)
        w("+    COMPUTE apl_basis = 'licensed formulation maximum per %s'." % interval)
        first = False
    for generic, interval, mx in lai:
        if (generic, interval_days.get(interval)) in lai_by_days:
            continue
        kw = "DO IF" if first else "ELSE IF"
        w("+  %s (apl_gen = '%s' AND apl_int = '%s')." % (kw, generic, interval))
        w("+    COMPUTE apl_ref = %.6f." % mx)
        w("+    COMPUTE apl_basis = 'licensed formulation maximum per %s'." % interval)
        first = False
    w("+  ELSE.")
    w("+    COMPUTE apl_flag = 4.")
    w("+  END IF.")
    w("END IF.")
    w("")
    w("* ---- 5. score ----------------------------------------------------------------.")
    w("")
    w("IF (apl_flag = 0 AND apl_ref > 0) apl_score = apl_dose / apl_ref * 100.")
    w("IF (apl_flag <> 0) apl_score = $SYSMIS.")
    w("NUMERIC apl_refused (F1.0).")
    w("COMPUTE apl_refused = (apl_flag <> 0).")
    w("")
    w("VARIABLE LABELS")
    w("  apl_gen 'AP_Load2026: matched generic'")
    w("  apl_stem 'AP_Load2026: stem that matched'")
    w("  apl_ref 'AP_Load2026: reference dose (mg)'")
    w("  apl_basis 'AP_Load2026: basis of the reference dose'")
    w("  apl_score 'AP_Load2026: score for this prescription (%)'")
    w("  apl_flag 'AP_Load2026: 0 = scored, >0 = refused (see header)'.")
    w("VALUE LABELS apl_flag")
    w("  0 'scored' 1 'drug not recognised' 2 'dose missing or not numeric'")
    w("  3 'oral or depot could not be told apart' 4 'depot interval missing or not tabulated'")
    w("  5 'sex missing (clozapine)' 6 'smoking missing (clozapine)'.")
    w("")
    w("* ---- 6. back to one row per patient ------------------------------------------.")
    w("")
    w("DATASET DECLARE apl_scores.")
    w("AGGREGATE OUTFILE = apl_scores")
    w("  /BREAK = patient_id")
    w("  /AP_Load2026 = SUM(apl_score)")
    w("  /drugs_scored = NU(apl_score)")
    w("  /rows_refused = SUM(apl_refused).")
    w("DATASET ACTIVATE apl_scores.")
    w("STRING complete (A3) reference_table (A8).")
    w("COMPUTE complete = 'yes'.")
    w("IF (rows_refused > 0) complete = 'NO'.")
    w("COMPUTE reference_table = '%s'." % TABLE_VERSION)
    w("VARIABLE LABELS")
    w("  AP_Load2026 'Antipsychotic Dose Load (pct), reference table %s'" % TABLE_VERSION)
    w("  rows_refused 'prescriptions that could not be scored'")
    w("  complete 'no prescription refused for this patient'.")
    w("EXECUTE.")
    w("")
    w("* A patient with rows_refused > 0 has an UNDERSTATED load. Report the counts:")
    w("FREQUENCIES VARIABLES = complete.")
    w("")
    w("* Reasons, for correction at source:")
    w("DATASET ACTIVATE apl_work.")
    w("FREQUENCIES VARIABLES = apl_flag.")
    w("TEMPORARY.")
    w("SELECT IF (apl_flag = 1).")
    w("FREQUENCIES VARIABLES = apl_drug.")
    w("")

    return "\n".join(L)


def main():
    text = render()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(text)
    print("wrote %s  (%d lines)" % (OUT, len(text.splitlines())))


if __name__ == "__main__":
    main()
