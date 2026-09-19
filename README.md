# AP_load
Antipsychotic load for schizophrenia research studies

Reference implementations of the Antipsychotic Dose Load (AP_Load2026), a normalised
prescribed-dose index for schizophrenia research, in **Python, R and SPSS**, with a
**browser calculator** for scoring a single regimen.

Each antipsychotic is scored as its prescribed daily dose expressed as a percentage of a
documented reference dose, and the percentages are summed across agents without an upper
cap. Clozapine is referenced to a target individualised for sex and cigarettes per day.
Other oral agents are referenced to the geometric mean of the licensed maximum and the
WHO Defined Daily Dose, capped at 1.5 × DDD. Long-acting injectables are referenced to
the licensed formulation maximum for the same dosing interval.

Reference tables are dated: `2026-09`.

## Quick start

**Python** — long format, reads free-text drug names and doses:

    python3 python/ap_load2026.py examples/table5_regimens.csv scores.csv \
        --detail-csv detail.csv --review-csv to_review.csv

**R** — identical behaviour, base R only, no packages:

    Rscript r/ap_load2026.R examples/table5_regimens.csv scores.csv detail.csv to_review.csv

R can also be sourced: `source("r/ap_load2026.R"); res <- ap_load(my_data)`.

**SPSS** — wide format, one row per patient, doses already numeric:

    INSERT FILE = 'spss/ap_load2026.sps'.

`scores.csv` holds one row per patient. `detail.csv` shows how every prescription was
scored — matched drug, reference dose, basis, percentage — so a single patient can be
checked by hand. `to_review.csv` holds only the rows the tool refused to score.

## Input

**Python and R** take one row per prescribed drug:

    patient_id, sex, cigarettes_per_day, drug, dose, route, interval

**SPSS** takes one row per patient with up to four slots: `AP_1 … AP_4`, `AP_1_dose …`,
`AP_1_route …`, `AP_1_interval …`, plus `sex` and `cigs_per_day`. It restructures them
internally with `VARSTOCASES`, so the scoring is the same single pass as in the other two.

`sex` may be text (`male`/`female`, `m`/`f`, `hombre`/`mujer`) or numeric, **1 = male,
0 = female**. Every row scored from a numeric code is annotated in the detail output, so
the convention used is visible rather than assumed.

`cigarettes_per_day` is preferred; `smoking_status` (yes/no, fumador) is accepted and
flagged as a binary approximation. Sex and smoking are required only for clozapine.

`route` and `interval` are optional but resolve ambiguity — see below.

`interval` may be written in either of the ways a schedule is normally named, in English
or Spanish: `monthly`, `4-weekly`, `every 4 weeks`, `q4w`, `28 days`, `mensual` all name
the same schedule, and a depot filed in the reference table under one of them is found by
any of them. The vocabulary is `reference/ap_load2026_intervals.csv`; add local spellings
there (and re-run `python3 build/generate_spss.py` if you use SPSS).

## What the tool refuses to do

Anything that cannot be resolved without guessing is refused, reported and left out of the
score. It is never silently scored as zero.

| Situation | Behaviour |
|---|---|
| drug name matches no stem | refused — add a row to `reference/ap_load2026_drug_stems.csv` |
| bare number for an agent with both oral and depot forms | refused — `Aripiprazole 400` is 100% monthly or 1,887% daily |
| bare number for an oral-only agent (clozapine, quetiapine) | accepted as a daily dose |
| depot identified but no interval stated | refused |
| clozapine without sex or smoking | refused |
| dose that is not a number | refused |
| `1,000 mg` or `1.000 mg` | refused — one thousand in one convention, one in the other |
| `300 mg bd`, `100-0-200`, `2 x 100 mg` | refused — a dose per administration is not the daily total |
| `10mg mane, 5mg nocte` | refused — one field, two doses |
| `30 ml`, `2 tablets` | refused — not a mass |
| `500 microgram`, `1 g` | accepted, converted to mg |
| `0`, `-100` | refused — omit the row instead |

The dose parser reads a number, optionally with a unit and a dosing schedule
(`450mg/d`, `400 mg/mes`, `960/2meses`), and refuses everything else. It does not
take the first number it can find: a dose read as 1 mg instead of 1,000 mg changes
a cohort mean and never announces itself, which is the failure this design exists
to prevent.

A cohort scored with rows refused is not comparable with one scored without any, so the
counts belong in your methods. They are in the console report and in the `rows_refused`
and `complete` columns of the patient output; in SPSS, in `apl_flag` and `rows_refused`.

## Drug names

Names are matched on **stems, anchored at the start of the string**, longest stem first:
`cloz` matches clozapine, clozapina, Clozaril; `arip` matches aripiprazole, aripiprazol and
the common misspelling aripriprazole. Matching is prefix-based rather than substring so that
*ami*sulpride is never read as sulpiride. Stems are at least four characters, so `clo` is
never used — it would catch clomipramine, clonazepam and clobazam.

The shipped table covers **English and Spanish** generic names and the brand names in common
use in both countries — Clozaril, Denzapine, Zaponex, Leponex; Largactil, Sinogan, Nozinan;
Dolmatil, Dogmatil, Digton; Modecate, Clopixol, Cisordinol, Depixol; Eskazine, Stelazine,
Semap, Solian, Latuda, Zeldox. Brand names that imply a formulation also set it: Trevicta
is three-monthly, Xeplion monthly, Consta two-weekly.

**Working in another country?** Add rows to `reference/ap_load2026_drug_stems.csv`, then
re-run `python3 build/generate_spss.py` if you use SPSS. Nothing else needs changing, and
the tool tells you which names it could not match.

## Local recalibration

The shipped tables are the reference configuration, for cross-study comparison. To score
against a local formulary, copy `reference/`, edit the CSVs and pass `--reference-dir`.
The configuration used is stamped into every output file; results from a recalibrated
table should be labelled as such.

`--anchors reeves` substitutes the Reeves-derived clozapine anchors for the
Rostami-Hodjegan-derived ones. In SPSS the alternative anchors are given as a comment
beside the clozapine block.

## The browser calculator

`web/` holds a calculator that scores one regimen at a time and shows the AP_Load2026
alongside DDD/day and %BNFmax. It is plain HTML, CSS and JavaScript, with nothing to
install and no data leaving the browser:

    web/index.html + web/apload.css + web/apload.js   a page to upload as it is
    web/apload-squarespace.html                       the same calculator as one file,
                                                      to paste into a Squarespace code
                                                      block (all styles scoped, so it
                                                      cannot disturb the rest of a site)

The DDD/day column converts a depot dose over the calendar month the WHO derives depot
DDDs on (30, 60, 90, 180 days), which is why it can differ slightly from a 28-day
convention. The AP_Load2026 score itself never uses those numbers.

## Keeping the four implementations identical

`reference/` is the single source of truth. Python and R read those CSVs at run time.
SPSS and the browser calculator cannot, so both are **generated** from the same CSVs:

    python3 build/generate_spss.py     # writes spss/ap_load2026.sps
    python3 build/generate_web.py      # writes the tables into web/apload.js, and
                                       # copies apload.js into the Squarespace build

Never edit the `.sps`, the tables in `apload.js`, or the Squarespace file by hand — edit
the reference tables and regenerate. `tests/test_generated.py` fails if a generated file
has fallen behind, so the drift cannot reach an analysis unnoticed.

## Verifying the installation

    sh tests/run_all.sh                # everything below, R and node optional

or one at a time:

    python3 tests/test_table5.py       # reproduces the 16 regimens of manuscript Table 5
    python3 tests/test_refusals.py     # confirms ambiguous input is refused, not guessed
    python3 tests/test_dose_parsing.py # doses that could mean two things are refused
    Rscript  tests/test_table5.R       # the same three tests in R
    Rscript  tests/test_refusals.R
    Rscript  tests/test_dose_parsing.R
    python3 tests/test_agreement.py    # Python and R must agree to the decimal
    python3 tests/test_generated.py    # SPSS and web tables match reference/
    node     tests/test_web.js         # the browser calculator reproduces Table 5

The Table 5 tests are the correctness check: the output must match the published table
exactly. The refusal and dose-parsing tests are the safety check. SPSS has no automated
test — run it on `examples/table5_regimens_wide.csv`, which is the same sixteen regimens
in wide format, and compare with `examples/table5_expected.csv`.

## Files

    reference/   the dated reference tables — the single source of truth
    python/      the implementation and command-line tool
    r/           the same, in base R
    spss/        generated syntax for SPSS
    web/         the browser calculator (generated tables)
    build/       the generators that write the SPSS syntax and the web tables
    examples/    the published Table 5 regimens (long and wide), a deliberately messy
                 file, and a file of doses written the awkward ways they really are
    tests/       correctness, refusal, cross-language and staleness tests

## Licence and citation

MIT, for the code (see `LICENSE`). The reference tables are compiled from the sources
named row by row in each file; the rights in those sources remain with their publishers.
Nothing here is a prescribing tool or a clinical decision aid.

Fernandez-Egea E, Krishnadas R, Jenkins C, Patel R, Cardinal RN, Wolpe N. The
Antipsychotic Dose Load (AP_Load2026): a normalised prescribed-dose index for
schizophrenia research. [details to be completed on acceptance]

`CITATION.cff` carries the same citation in machine-readable form, for GitHub and Zenodo.
